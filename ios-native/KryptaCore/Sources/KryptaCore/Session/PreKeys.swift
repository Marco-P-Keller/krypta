import Foundation

/// Das Bündel in `prekeys/{uid}` — gleiche Feldnamen wie PreKeyBundle.toMap.
public struct PreKeyBundle: Equatable, Sendable {
    public let identityPublicKey: Data
    public let signedPreKeyPublic: Data
    public let signedPreKeySignature: Data
    public let signedPreKeyId: Int
    /// Ed25519-Schlüssel zur Signaturprüfung. Ohne ihn (v1) wird abgelehnt.
    public let signingPublicKey: Data?

    public init(identityPublicKey: Data, signedPreKeyPublic: Data, signedPreKeySignature: Data, signedPreKeyId: Int, signingPublicKey: Data?) {
        self.identityPublicKey = identityPublicKey
        self.signedPreKeyPublic = signedPreKeyPublic
        self.signedPreKeySignature = signedPreKeySignature
        self.signedPreKeyId = signedPreKeyId
        self.signingPublicKey = signingPublicKey
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
            signingPublicKey: map["sigPk"]?.stringValue.flatMap(Data.init(base64:))
        )
    }

    /// Signaturprüfung des signierten Vorabschlüssels. Ohne Ed25519-Schlüssel
    /// immer `false`: der alte v1-Weg war fälschbar.
    public var hasValidSignature: Bool {
        guard let signingPublicKey else { return false }
        return Primitives.ed25519Verify(signature: signedPreKeySignature, message: signedPreKeyPublic, publicKey: signingPublicKey)
    }
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
    }

    public func find(id: Int, now: Date = Date()) -> SignedPreKey? {
        if current?.id == id { return current }
        return previous.first { $0.id == id && now.timeIntervalSince($0.createdAt) <= Self.overlap }
    }

    /// Das Bündel zum Veröffentlichen, signiert mit dem Identitätsseed.
    public func bundle(identity: KeyPair) throws -> PreKeyBundle {
        guard let current else { throw CryptoError.malformed("no signed prekey") }
        let (signature, signingKey) = try Primitives.ed25519Sign(message: current.publicKey, seed: identity.privateKey)
        return PreKeyBundle(
            identityPublicKey: identity.publicKey,
            signedPreKeyPublic: current.publicKey,
            signedPreKeySignature: signature,
            signedPreKeyId: current.id,
            signingPublicKey: signingKey
        )
    }
}
