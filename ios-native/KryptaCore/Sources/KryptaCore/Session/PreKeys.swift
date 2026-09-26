import Foundation

/// Das Bündel in `prekeys/{uid}` — gleiche Feldnamen wie PreKeyBundle.toMap.
public struct PreKeyBundle: Equatable, Sendable {
    public let identityPublicKey: Data
    public let signedPreKeyPublic: Data
    public let signedPreKeySignature: Data
    public let signedPreKeyId: Int
    /// Ed25519-Schlüssel zur Signaturprüfung. Ohne ihn (v1) wird abgelehnt.
    public let signingPublicKey: Data?
    /// ML-KEM-768 zum selben `spkId` (`pqpk`), nur von nativen Geräten ab
    /// iOS 26. Die Flutter-Fassung liest das Feld nicht.
    public let postQuantumPreKey: Data?
    public let postQuantumSignature: Data?

    public init(identityPublicKey: Data, signedPreKeyPublic: Data, signedPreKeySignature: Data, signedPreKeyId: Int, signingPublicKey: Data?,
                postQuantumPreKey: Data? = nil, postQuantumSignature: Data? = nil) {
        self.identityPublicKey = identityPublicKey
        self.signedPreKeyPublic = signedPreKeyPublic
        self.signedPreKeySignature = signedPreKeySignature
        self.signedPreKeyId = signedPreKeyId
        self.signingPublicKey = signingPublicKey
        self.postQuantumPreKey = postQuantumPreKey
        self.postQuantumSignature = postQuantumSignature
    }

    /// Einmal-Vorabschlüssel (`opk`) werden bewusst weder geschrieben noch
    /// gelesen — siehe Build-61-Zustellfehler in session_handshake_service.dart.
    public var json: JSONObject {
        var map: JSONObject = [
            "ik": .string(identityPublicKey.base64),
            "spk": .string(signedPreKeyPublic.base64),
            "spks": .string(signedPreKeySignature.base64),
            "spkId": .int(signedPreKeyId),
        ]
        if let signingPublicKey { map["sigPk"] = .string(signingPublicKey.base64) }
        if let postQuantumPreKey, let postQuantumSignature {
            map["pqpk"] = .string(postQuantumPreKey.base64)
            map["pqs"] = .string(postQuantumSignature.base64)
        }
        return map
    }

    public init(json map: JSONObject) throws {
        guard
            let ik = map["ik"]?.stringValue.flatMap(Data.init(base64:)),
            let spk = map["spk"]?.stringValue.flatMap(Data.init(base64:)),
            let spks = map["spks"]?.stringValue.flatMap(Data.init(base64:)),
            let spkId = map["spkId"]?.intValue
        else { throw CryptoError.malformed("prekey bundle") }
        self.init(
            identityPublicKey: ik,
            signedPreKeyPublic: spk,
            signedPreKeySignature: spks,
            signedPreKeyId: spkId,
            signingPublicKey: map["sigPk"]?.stringValue.flatMap(Data.init(base64:)),
            postQuantumPreKey: map["pqpk"]?.stringValue.flatMap(Data.init(base64:)),
            postQuantumSignature: map["pqs"]?.stringValue.flatMap(Data.init(base64:))
        )
    }

    /// Signaturprüfung des signierten Vorabschlüssels. Ohne Ed25519-Schlüssel
    /// immer `false`: der alte v1-Weg war fälschbar.
    public var hasValidSignature: Bool {
        guard let signingPublicKey else { return false }
        return Primitives.ed25519Verify(signature: signedPreKeySignature, message: signedPreKeyPublic, publicKey: signingPublicKey)
    }

    /// Der ML-KEM-Schlüssel ist da, hat die richtige Länge und ist mit
    /// demselben Ed25519-Schlüssel signiert wie der Vorabschlüssel — an
    /// dessen `spkId` gebunden, damit der Server nicht alt und neu mischt.
    public var hasValidPostQuantumKey: Bool {
        guard hasValidSignature, let signingPublicKey, let postQuantumPreKey, let postQuantumSignature,
              postQuantumPreKey.count == PostQuantum.publicKeyLength else { return false }
        return Primitives.ed25519Verify(
            signature: postQuantumSignature,
            message: Self.postQuantumSigningMessage(id: signedPreKeyId, key: postQuantumPreKey),
            publicKey: signingPublicKey
        )
    }

    static func postQuantumSigningMessage(id: Int, key: Data) -> Data {
        "KryptaPQ-v1".utf8Data + Data.bigEndian(UInt32(truncatingIfNeeded: id)) + key
    }
}

/// ML-KEM-768-Vorabschlüssel. Er gehört zum signierten Vorabschlüssel mit
/// derselben `id`, wird mit ihm rotiert und mit ihm verworfen.
public struct PostQuantumPreKey: Equatable, Sendable, Codable {
    public let id: Int
    public let publicKey: Data
    public let seed: Data
    public let createdAt: Date
}

/// Ein signierter Vorabschlüssel mit privatem Teil (bleibt auf dem Gerät).
public struct SignedPreKey: Equatable, Sendable, Codable {
    public let id: Int
    public let publicKey: Data
    public let privateKey: Data
    public let createdAt: Date

    public init(id: Int, publicKey: Data, privateKey: Data, createdAt: Date) {
        self.id = id
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.createdAt = createdAt
    }
}

/// Verwaltet die eigenen signierten Vorabschlüssel.
///
/// Rotation alle sieben Tage, der vorige bleibt 48 Stunden gültig, damit
/// Sitzungen, die gerade gegen ihn eröffnet wurden, noch ankommen.
public struct PreKeyStore: Equatable, Sendable, Codable {
    public static let rotation: TimeInterval = 7 * 24 * 3600
    public static let overlap: TimeInterval = 48 * 3600

    public private(set) var current: SignedPreKey?
    public private(set) var previous: [SignedPreKey] = []
    public private(set) var nextId = 0
    /// Optional, damit ältere gespeicherte Stände weiter lesbar sind.
    public private(set) var postQuantumKeys: [PostQuantumPreKey]?

    public init() {}

    /// Übernahme eines vorhandenen Zustands (Flutter-Daten).
    public init(current: SignedPreKey?, previous: [SignedPreKey], nextId: Int) {
        self.current = current
        self.previous = previous
        self.nextId = max(nextId, (([current].compactMap { $0 } + previous).map(\.id).max() ?? -1) + 1)
    }

    public func needsRotation(now: Date = Date()) -> Bool {
        guard let current else { return true }
        return now.timeIntervalSince(current.createdAt) > Self.rotation
    }

    public mutating func rotate(now: Date = Date()) -> SignedPreKey {
        if let current { previous.append(current) }
        prune(now: now)
        let kp = KeyPair.generate()
        let spk = SignedPreKey(id: nextId, publicKey: kp.publicKey, privateKey: kp.privateKey, createdAt: now)
        nextId += 1
        current = spk
        return spk
    }

    /// Setzt einen vorhandenen Schlüssel als aktuellen ein (Tests, Übernahme).
    public mutating func install(_ key: SignedPreKey) {
        if let current { previous.append(current) }
        current = key
        nextId = max(nextId, key.id + 1)
    }

    public mutating func prune(now: Date = Date()) {
        previous.removeAll { now.timeIntervalSince($0.createdAt) > Self.overlap }
        let live = Set(([current].compactMap { $0 } + previous).map(\.id))
        postQuantumKeys?.removeAll { !live.contains($0.id) }
    }

    /// Sorgt dafür, dass zum aktuellen Vorabschlüssel ein ML-KEM-Schlüssel
    /// existiert (ab iOS 26). `true`, wenn sich etwas geändert hat.
    public mutating func ensurePostQuantum(now: Date = Date()) -> Bool {
        guard PostQuantum.isAvailable, let current,
              postQuantumKeys?.contains(where: { $0.id == current.id }) != true,
              let pair = try? PostQuantum.generate() else { return false }
        postQuantumKeys = (postQuantumKeys ?? []) + [PostQuantumPreKey(id: current.id, publicKey: pair.publicKey, seed: pair.seed, createdAt: now)]
        prune(now: now)
        return true
    }

    /// Der ML-KEM-Schlüssel zu einem noch gültigen Vorabschlüssel.
    public func findPostQuantum(id: Int, now: Date = Date()) -> PostQuantumPreKey? {
        guard find(id: id, now: now) != nil else { return nil }
        return postQuantumKeys?.first { $0.id == id }
    }

    public func find(id: Int, now: Date = Date()) -> SignedPreKey? {
        if current?.id == id { return current }
        return previous.first { $0.id == id && now.timeIntervalSince($0.createdAt) <= Self.overlap }
    }

    /// Das Bündel zum Veröffentlichen, signiert mit dem Identitätsseed.
    public func bundle(identity: KeyPair) throws -> PreKeyBundle {
        guard let current else { throw CryptoError.malformed("no signed prekey") }
        let (signature, signingKey) = try Primitives.ed25519Sign(message: current.publicKey, seed: identity.privateKey)
        var pqKey: Data?, pqSignature: Data?
        if let pq = postQuantumKeys?.first(where: { $0.id == current.id }) {
            pqKey = pq.publicKey
            pqSignature = try Primitives.ed25519Sign(
                message: PreKeyBundle.postQuantumSigningMessage(id: current.id, key: pq.publicKey), seed: identity.privateKey
            ).signature
        }
        return PreKeyBundle(
            identityPublicKey: identity.publicKey,
            signedPreKeyPublic: current.publicKey,
            signedPreKeySignature: signature,
            signedPreKeyId: current.id,
            signingPublicKey: signingKey,
            postQuantumPreKey: pqKey,
            postQuantumSignature: pqSignature
        )
    }
}
