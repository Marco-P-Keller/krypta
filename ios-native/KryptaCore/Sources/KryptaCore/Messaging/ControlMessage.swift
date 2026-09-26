import Foundation

/// Steuernachricht (Zustellung, Lesen, Löschen …), HMAC-signiert und mit
/// Zähler — wie security/messaging/control_message.dart.
public struct ControlMessage: Equatable, Sendable {
    public let type: String
    public let chatId: String
    public let messageId: String
    public let senderId: String
    public let timestamp: Int
    public let counter: Int
    public let signature: String

    public static func create(type: String, chatId: String, messageId: String, senderId: String, counter: Int, key: Data, now: Date = Date()) -> ControlMessage {
        let ts = Int(now.timeIntervalSince1970 * 1000)
        return ControlMessage(
            type: type, chatId: chatId, messageId: messageId, senderId: senderId,
            timestamp: ts, counter: counter,
            signature: sign(type, chatId, messageId, senderId, ts, counter, key: key)
        )
    }

    public func verify(key: Data) -> Bool {
        let expected = Self.sign(type, chatId, messageId, senderId, timestamp, counter, key: key)
        return signature.utf8Data.constantTimeEquals(expected.utf8Data)
    }

    public enum ValidationError: String, Error {
        case senderMismatch = "sender_mismatch"
        case replay = "replay_detected"
        case expired = "message_expired"
        case future = "future_timestamp"
    }

    public func validate(expectedSenderId: String, lastSeenCounter: Int, maxAge: TimeInterval, now: Date = Date()) -> ValidationError? {
        if senderId != expectedSenderId { return .senderMismatch }
        if counter <= lastSeenCounter { return .replay }
        let age = Int(now.timeIntervalSince1970 * 1000) - timestamp
        if age > Int(maxAge * 1000) { return .expired }
        if age < -30_000 { return .future }
        return nil
    }

    public var json: JSONObject {
        [
            "type": .string(type), "chatId": .string(chatId), "mid": .string(messageId),
            "sid": .string(senderId), "ts": .int(timestamp), "ctr": .int(counter), "sig": .string(signature),
        ]
    }

    public init(json map: JSONObject) throws {
        guard
            let type = map["type"]?.stringValue, let chatId = map["chatId"]?.stringValue,
            let mid = map["mid"]?.stringValue, let sid = map["sid"]?.stringValue,
            let ts = map["ts"]?.intValue, let ctr = map["ctr"]?.intValue,
            let sig = map["sig"]?.stringValue, !sig.isEmpty
        else { throw CryptoError.malformed("control message") }
        self.init(type: type, chatId: chatId, messageId: mid, senderId: sid, timestamp: ts, counter: ctr, signature: sig)
    }

    init(type: String, chatId: String, messageId: String, senderId: String, timestamp: Int, counter: Int, signature: String) {
        self.type = type
        self.chatId = chatId
        self.messageId = messageId
        self.senderId = senderId
        self.timestamp = timestamp
        self.counter = counter
        self.signature = signature
    }

    static func sign(_ type: String, _ chatId: String, _ mid: String, _ sid: String, _ ts: Int, _ ctr: Int, key: Data) -> String {
        Primitives.hmacSHA256(key: key, message: "\(type)|\(chatId)|\(mid)|\(sid)|\(ts)|\(ctr)".utf8Data).base64
    }

    /// Paarschlüssel für Steuernachrichten: DH der Identitäten, HKDF mit
    /// den sortierten Kennungen beider Seiten im Info-Feld.
    public static func pairKey(identity: KeyPair, peerIdentityPublicKey: Data, ownId: String, peerId: String) throws -> Data {
        var shared = try Primitives.dh(privateKey: identity.privateKey, publicKey: peerIdentityPublicKey)
        defer { shared.zero() }
        let tag = [ownId, peerId].sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }.joined(separator: "|")
        return Primitives.hkdfSHA256(ikm: shared, salt: Data(count: 32), info: "KryptaControlHMAC-v2|\(tag)".utf8Data, length: 32)
    }
}

/// Wie lange eine Steuernachricht gilt — ControlMessagePolicy in Dart.
public enum ControlMessagePolicy {
    public static let short: TimeInterval = 5 * 60
    public static let long: TimeInterval = 30 * 24 * 3600
    public static let stateChanging: Set<String> = [
        "chatGone", "burned", "unlock", "delete", "clearMine", "gone", "accepted", "delivered",
    ]

    public static func maxAge(_ type: String) -> TimeInterval {
        stateChanging.contains(type) || type.hasPrefix("sdChanged:") ? long : short
    }
}

/// Zähler je Chat: gesendet und zuletzt gesehen.
public struct ControlCounter: Codable, Equatable, Sendable {
    public private(set) var sent: [String: Int] = [:]
    public private(set) var lastSeen: [String: Int] = [:]

    public init() {}

    public mutating func next(for chatId: String) -> Int {
        let n = (sent[chatId] ?? 0) + 1
        sent[chatId] = n
        return n
    }

    public func lastSeen(for chatId: String) -> Int { lastSeen[chatId] ?? 0 }

    /// `false` bei Wiedereinspielen.
    public mutating func record(_ counter: Int, for chatId: String) -> Bool {
        guard counter > lastSeen(for: chatId) else { return false }
        lastSeen[chatId] = counter
        return true
    }

    public mutating func forget(chatId: String) {
        sent.removeValue(forKey: chatId)
        lastSeen.removeValue(forKey: chatId)
    }
}
