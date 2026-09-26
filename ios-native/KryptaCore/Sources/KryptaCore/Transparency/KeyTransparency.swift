import Foundation

/// Ein signierter, verketteter Eintrag im Schlüsselprotokoll —
/// security/transparency/key_commitment.dart, Byte für Byte.
///
/// Jeder Eintrag nennt den Hash seines Vorgängers; der Server kann deshalb
/// nichts einfügen, entfernen oder umstellen, ohne dass die Kette reißt.
/// Signiert wird mit dem Ed25519-Schlüssel aus dem Identitätsseed.
public struct KeyCommitment: Equatable, Sendable {
    public static let currentVersion = 2

    public let version: Int
    public let epoch: Int
    public let identityPublicKey: Data
    public let previousCommitHash: Data
    public let timestampMs: Int
    public let signature: Data
    public let signingPublicKey: Data

    public static var genesisHash: Data { Data(count: 32) }

    public init(version: Int, epoch: Int, identityPublicKey: Data, previousCommitHash: Data, timestampMs: Int, signature: Data, signingPublicKey: Data) {
        self.version = version
        self.epoch = epoch
        self.identityPublicKey = identityPublicKey.detached
        self.previousCommitHash = previousCommitHash.detached
        self.timestampMs = timestampMs
        self.signature = signature.detached
        self.signingPublicKey = signingPublicKey.detached
    }

    /// v1: version ‖ epoch(8 BE) ‖ ik(32) ‖ prev(32) ‖ ts(8 BE) = 81 Byte.
    /// v2: v1 ‖ signingPublicKey(32) = 113 Byte — die Signatur deckt den
    /// Signaturschlüssel mit ab (H1-Crypto).
    public var canonicalBytes: Data {
        var out = Data([UInt8(truncatingIfNeeded: version)])
        out += Data.bigEndian(Int64(epoch))
        out += identityPublicKey
        out += previousCommitHash
        out += Data.bigEndian(Int64(timestampMs))
        if version >= 2 { out += signingPublicKey }
        return out
    }

    public var commitHash: Data { Primitives.sha256(canonicalBytes) }

    public var isGenesis: Bool { epoch == 0 && previousCommitHash.isAllZero }

    /// Neuer Eintrag, signiert mit dem Identitätsseed.
    public static func create(epoch: Int, identity: KeyPair, previousHash: Data, now: Date = Date()) throws -> KeyCommitment {
        let signingKey = try Primitives.ed25519PublicKey(seed: identity.privateKey)
        let unsigned = KeyCommitment(
            version: currentVersion, epoch: epoch, identityPublicKey: identity.publicKey,
            previousCommitHash: previousHash, timestampMs: Int(now.timeIntervalSince1970 * 1000),
            signature: Data(), signingPublicKey: signingKey
        )
        let (signature, _) = try Primitives.ed25519Sign(message: unsigned.canonicalBytes, seed: identity.privateKey)
        return KeyCommitment(
            version: unsigned.version, epoch: epoch, identityPublicKey: unsigned.identityPublicKey,
            previousCommitHash: previousHash, timestampMs: unsigned.timestampMs,
            signature: signature, signingPublicKey: signingKey
        )
    }

    public var hasValidSignature: Bool {
        Primitives.ed25519Verify(signature: signature, message: canonicalBytes, publicKey: signingPublicKey)
    }

    /// Wie `toMap` in Dart — so liegt der Eintrag auch in Firestore.
    public var json: JSONObject {
        [
            "v": .int(version),
            "e": .int(epoch),
            "k": .string(identityPublicKey.base64),
            "p": .string(previousCommitHash.base64),
            "ts": .int(timestampMs),
            "s": .string(signature.base64),
            "sp": .string(signingPublicKey.base64),
        ]
    }

    /// Einträge ohne `v` stammen aus der Zeit vor v2 und sind v1.
    public init(json map: JSONObject) throws {
        guard
            let e = map["e"]?.intValue,
            let k = map["k"]?.stringValue.flatMap(Data.init(base64:)),
            let p = map["p"]?.stringValue.flatMap(Data.init(base64:)),
            let ts = map["ts"]?.intValue,
            let s = map["s"]?.stringValue.flatMap(Data.init(base64:)),
            let sp = map["sp"]?.stringValue.flatMap(Data.init(base64:))
        else { throw CryptoError.malformed("key commitment") }
        self.init(version: map["v"]?.intValue ?? 1, epoch: e, identityPublicKey: k, previousCommitHash: p, timestampMs: ts, signature: s, signingPublicKey: sp)
    }
}

public enum CommitmentVerifyResult: Equatable, Sendable {
    case valid, signatureInvalid, chainBroken, epochViolation, keyMismatch, malformed
    case signingKeyChanged, legacyBootstrapRejected
}

/// Die lokal geprüfte Kette eines Nutzers samt festgehaltenem
/// Signaturschlüssel (TOFU) — KeyTransparencyLog in Dart.
public struct TransparencyChain: Equatable, Sendable {
    public private(set) var entries: [KeyCommitment] = []
    /// Der Ed25519-Schlüssel, der die Kette verlängern darf. Liegt neben der
    /// Kette, weil v1-Einträge ihn nicht mitsignieren.
    public private(set) var signingPin: Data?

    public init(entries: [KeyCommitment] = [], signingPin: Data? = nil) {
        self.entries = entries
        // Bestand ohne Pin: der Signaturschlüssel des ersten Eintrags gilt.
        self.signingPin = signingPin ?? entries.first?.signingPublicKey
    }

    public var head: KeyCommitment? { entries.last }
    public var latestEpoch: Int { head?.epoch ?? -1 }
    public var headHash: Data { head?.commitHash ?? KeyCommitment.genesisHash }

    public func entry(at epoch: Int) -> KeyCommitment? { entries.first { $0.epoch == epoch } }

    /// Prüfen und anhängen — fail-closed, in derselben Reihenfolge wie Dart.
    public mutating func verifyAndAppend(_ c: KeyCommitment, expectedPublicKey: Data?) -> CommitmentVerifyResult {
        guard c.identityPublicKey.count == 32, c.previousCommitHash.count == 32,
              !c.signature.isEmpty, c.signingPublicKey.count == 32 else { return .malformed }
        guard c.hasValidSignature else { return .signatureInvalid }
        guard c.epoch == (head.map { $0.epoch + 1 } ?? 0) else { return .epochViolation }
        guard c.previousCommitHash.constantTimeEquals(headHash) else { return .chainBroken }
        if let expectedPublicKey, !c.identityPublicKey.constantTimeEquals(expectedPublicKey) { return .keyMismatch }
        if let signingPin {
            guard c.signingPublicKey.constantTimeEquals(signingPin) else { return .signingKeyChanged }
        } else if c.version < 2 {
            // Der erste Pin darf nur aus einem Eintrag kommen, dessen
            // Signatur den Signaturschlüssel mit abdeckt.
            return .legacyBootstrapRejected
        }
        entries.append(c)
        if signingPin == nil { signingPin = c.signingPublicKey }
        return .valid
    }

    /// Ganze Kette prüfen; Index der ersten schadhaften Stelle oder `nil`.
    public func audit() -> Int? {
        guard let first = entries.first else { return nil }
        guard first.isGenesis, first.hasValidSignature else { return 0 }
        let pin = signingPin ?? first.signingPublicKey
        guard first.signingPublicKey.constantTimeEquals(pin) else { return 0 }
        for i in entries.indices.dropFirst() {
            let prev = entries[i - 1], cur = entries[i]
            if cur.epoch != prev.epoch + 1 || !cur.previousCommitHash.constantTimeEquals(prev.commitHash)
                || !cur.hasValidSignature || !cur.signingPublicKey.constantTimeEquals(pin) { return i }
        }
        return nil
    }

    /// Speicherform: dieselben Felder wie `kt_log_*` und `kt_pin_*` in Dart.
    public var json: JSONObject {
        var map: JSONObject = ["log": .array(entries.map { .object($0.json) })]
        if let signingPin { map["pin"] = .string(signingPin.base64) }
        return map
    }

    public init(json map: JSONObject) throws {
        let entries = try (map["log"]?.arrayValue ?? []).map { value -> KeyCommitment in
            guard let o = value.objectValue else { throw CryptoError.malformed("key commitment") }
            return try KeyCommitment(json: o)
        }
        self.init(entries: entries, signingPin: map["pin"]?.stringValue.flatMap(Data.init(base64:)))
    }
}

/// Was ein Kontakt über eine Kette gesehen hat — ConsistencyProof in Dart.
public struct ConsistencyProof: Equatable, Sendable {
    public let userId: String
    public let epoch: Int
    public let commitHash: Data

    public init(userId: String, epoch: Int, commitHash: Data) {
        self.userId = userId
        self.epoch = epoch
        self.commitHash = commitHash
    }

    public init?(chain: TransparencyChain, userId: String) {
        guard let head = chain.head else { return nil }
        self.init(userId: userId, epoch: head.epoch, commitHash: head.commitHash)
    }

    public var json: JSONObject { ["u": .string(userId), "e": .int(epoch), "h": .string(commitHash.base64)] }

    public init?(json map: JSONObject) {
        guard let u = map["u"]?.stringValue, let e = map["e"]?.intValue,
              let h = map["h"]?.stringValue.flatMap(Data.init(base64:)) else { return nil }
        self.init(userId: u, epoch: e, commitHash: h)
    }
}

public enum ConsistencyResult: Equatable, Sendable {
    case consistent, localBehind, remoteBehind, splitView, noProof
}

public extension TransparencyChain {
    /// Fremde Sicht gegen die eigene. Gleiche Epoche, anderer Hash heißt:
    /// der Server zeigt verschiedenen Leuten verschiedene Schlüssel.
    func check(_ proof: ConsistencyProof) -> ConsistencyResult {
        guard let head else { return .noProof }
        if head.epoch == proof.epoch {
            return head.commitHash.constantTimeEquals(proof.commitHash) ? .consistent : .splitView
        }
        if head.epoch < proof.epoch { return .localBehind }
        guard let mine = entry(at: proof.epoch) else { return .remoteBehind }
        return mine.commitHash.constantTimeEquals(proof.commitHash) ? .remoteBehind : .splitView
    }
}

/// Der Klatsch in jeder Nachricht (`_kt`): wie ich die Kette der
/// Empfängerin sehe (`rp`) und meine eigene (`sp`).
public enum TransparencyGossip {
    public static func payload(recipient: ConsistencyProof?, own: ConsistencyProof?) -> JSONObject? {
        guard recipient != nil || own != nil else { return nil }
        var map: JSONObject = [:]
        if let recipient { map["rp"] = .object(recipient.json) }
        if let own { map["sp"] = .object(own.json) }
        return map
    }

    public static func proofs(in map: JSONObject) -> [ConsistencyProof] {
        ["rp", "sp"].compactMap { map[$0]?.objectValue.flatMap(ConsistencyProof.init(json:)) }
    }

    /// Fingerabdruck der ganzen Kette zum Vergleichen: SHA-256 aller
    /// Eintragshashes, die ersten 16 Byte als Hex mit Doppelpunkten.
    public static func fingerprint(_ chain: TransparencyChain) -> String? {
        guard !chain.entries.isEmpty else { return nil }
        let all = chain.entries.reduce(into: Data()) { $0 += $1.commitHash }
        return Primitives.sha256(all).prefix(16).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
