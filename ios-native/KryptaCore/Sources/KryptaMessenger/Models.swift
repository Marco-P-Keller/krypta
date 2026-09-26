import Foundation
import KryptaCore

public enum TrustState: String, Codable, Sendable {
    case unverified, verified, keyChanged, blocked
}

/// Wo eine Kontaktanfrage steht (docs/KONTAKTANFRAGEN.md der Flutter-Fassung).
public enum RequestState: String, Codable, Sendable {
    case established, outgoing, incoming, declined
}

public enum VerificationMethod: String, Codable, Sendable {
    case qrCode, safetyNumber, manual
}

public struct Contact: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var displayName: String
    public var publicKey: Data
    public let addedAt: Date
    public var trustState: TrustState = .unverified
    public var trustBeforeBlock: TrustState?
    public var requestState: RequestState = .established
    public var declineCount = 0
    public var verifiedAt: Date?
    public var verificationMethod: VerificationMethod?
    public var verifiedFingerprint: String?
    public var previousPublicKey: Data?
    public var firstSeenIdentityKey: Data?
    public var lastKeyChangeAt: Date?
    public var safetyNumberVersion: Int?
    public var keyChangeCount = 0
    public var isGone = false
    public var goneAt: Date?
    /// Key Transparency: `nil` noch nicht geprüft, `false` Widerspruch
    /// gefunden, `true` Kette geprüft bis `lastVerifiedEpoch`.
    public var transparencyVerified: Bool?
    public var lastVerifiedEpoch: Int?

    public init(id: String, publicKey: Data, requestState: RequestState, trustState: TrustState = .unverified, now: Date = Date()) {
        self.id = id
        self.displayName = Contact.defaultName(for: id)
        self.publicKey = publicKey
        self.addedAt = now
        self.requestState = requestState
        self.trustState = trustState
        self.firstSeenIdentityKey = publicKey
    }

    public static func defaultName(for id: String) -> String { "User \(id.prefix(6))" }

    /// SHA-256 des Schlüssels, klein-hex — das `fp` im QR-Code.
    public static func fullFingerprint(_ key: Data) -> String {
        Primitives.sha256(key).map { String(format: "%02x", $0) }.joined()
    }

    /// Kurzform zum Anzeigen: die ersten acht Bytes.
    public var shortFingerprint: String {
        Primitives.sha256(publicKey).prefix(8).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Bestätigt heißt: bestätigt **für genau diesen Schlüssel**.
    public var isVerified: Bool {
        trustState == .verified && verifiedFingerprint == Contact.fullFingerprint(publicKey)
    }

    public var isBlocked: Bool { trustState == .blocked }
    public var hasKeyChanged: Bool { trustState == .keyChanged }

    public var canSendMessages: Bool {
        !isGone && trustState != .keyChanged && trustState != .blocked && requestState == .established
    }

    /// Schlüsselwechsel: die Bestätigung fällt, gesperrt bleibt gesperrt.
    mutating func markKeyChanged(newKey: Data?, now: Date = Date()) {
        if trustState == .blocked {
            trustBeforeBlock = .keyChanged
        } else {
            trustState = .keyChanged
        }
        if let newKey {
            previousPublicKey = publicKey
            publicKey = newKey
            keyChangeCount += 1
        }
        verifiedAt = nil
        verificationMethod = nil
        verifiedFingerprint = nil
        safetyNumberVersion = nil
        lastKeyChangeAt = now
    }
}

public enum MessageStatus: String, Codable, Sendable {
    case sending, sent, delivered, read, failed
}

public enum SystemEventKind: String, Codable, Sendable {
    case screenshot, screenRecording, accountDeleted, selfDestructChanged, selfDestructAfterRead
}

public struct Message: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let chatId: String
    public let senderId: String
    public let recipientId: String
    /// Klartext — bei Passwort-Nachrichten bis zum Entsperren der Blob.
    public var text: String?
    public let timestamp: Date
    public var status: MessageStatus
    public var deliveredAt: Date?
    public var readAt: Date?
    public var selfDestruct: TimeInterval?
    public var selfDestructFromChat = false
    public var burnAfterRead = false
    public var oneTime = false
    public var isPasswordProtected = false
    public var passwordUnlocked = true
    public var systemEvent: SystemEventKind?

    public var isSystemEvent: Bool { systemEvent != nil }
    public func isMine(_ me: String) -> Bool { senderId == me }

    public init(id: String, chatId: String, senderId: String, recipientId: String, text: String?, timestamp: Date, status: MessageStatus) {
        self.id = id
        self.chatId = chatId
        self.senderId = senderId
        self.recipientId = recipientId
        self.text = text
        self.timestamp = timestamp
        self.status = status
    }
}

public struct Chat: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let recipientId: String
    public var name: String
    public var lastActivity: Date?
    /// Chat-Regel: Frist für neue Nachrichten, „nach dem Lesen" und die
    /// Version, mit der beide Seiten sich einigen.
    public var timer: TimeInterval?
    public var timerSetAt: Date?
    public var deleteAfterRead = false
    public var ruleVersion = 0

    public init(id: String = UUID().uuidString.lowercased(), recipientId: String, name: String) {
        self.id = id
        self.recipientId = recipientId
        self.name = name
    }

    public var ruleIsEphemeral: Bool { timer != nil || deleteAfterRead }
}

/// Wie eine einzelne Nachricht gehen soll.
public struct SendOptions: Equatable, Sendable {
    public var selfDestruct: TimeInterval?
    public var fromChatRule = false
    public var burnAfterRead = false
    public var oneTime = false
    public var password: String?

    public init(selfDestruct: TimeInterval? = nil, fromChatRule: Bool = false, burnAfterRead: Bool = false, oneTime: Bool = false, password: String? = nil) {
        self.selfDestruct = selfDestruct
        self.fromChatRule = fromChatRule
        self.burnAfterRead = burnAfterRead
        self.oneTime = oneTime
        self.password = password
    }

    public static let plain = SendOptions()
}

/// Die Regeln der Löschfristen — SelfDestructPolicy der Flutter-Fassung.
public enum SelfDestructPolicy {
    public static let minimum: TimeInterval = 10
    public static let maximum: TimeInterval = 30 * 24 * 3600

    /// Ablauf ab Zustellung; eine spätere Chat-Regel startet ab ihrem Setzen.
    public static func deadline(_ m: Message, chat: Chat?) -> Date? {
        if m.isSystemEvent || m.oneTime { return nil }
        let frist = m.selfDestructFromChat ? (chat?.timer ?? m.selfDestruct) : (m.selfDestruct ?? chat?.timer)
        guard let frist, let delivered = m.deliveredAt else { return nil }
        let start = chat?.timerSetAt.map { max($0, delivered) } ?? delivered
        return start.addingTimeInterval(frist)
    }

    /// Eine fremde Frist wird auf ein vernünftiges Maß gekappt.
    public static func clamp(ms: Int) -> TimeInterval? {
        guard ms > 0 else { return nil }
        return min(max(Double(ms) / 1000, minimum), maximum)
    }

    /// Zustellzeitpunkt aus einer fremden Uhr: nicht vor dem Senden, nicht in der Zukunft.
    public static func deliveredAt(reported: Date, sent: Date, now: Date) -> Date {
        min(max(reported, sent), now)
    }

    static func isEphemeral(_ m: Message) -> Bool {
        !m.isSystemEvent && (m.selfDestruct != nil || m.burnAfterRead || m.oneTime)
    }

    /// Der Empfänger meldet den Ablauf an den Absender.
    static func announceBurn(_ m: Message, me: String, chatEphemeral: Bool) -> Bool {
        (isEphemeral(m) || (chatEphemeral && !m.isSystemEvent)) && m.senderId != me
    }

    /// Der Absender nimmt eine Ablaufmeldung nur für eigene, vergängliche Nachrichten an.
    static func acceptBurn(_ m: Message, me: String, chatEphemeral: Bool) -> Bool {
        m.senderId == me && (isEphemeral(m) || (chatEphemeral && !m.isSystemEvent))
    }

    static func afterReadDue(_ m: Message, ruleAfterRead: Bool) -> Bool {
        ruleAfterRead && !m.isSystemEvent && !m.oneTime && m.readAt != nil
    }

    // MARK: Chat-Regel als Steuernachricht: "sdChanged:<wert>:<version>"

    static func ruleType(timer: TimeInterval?, afterRead: Bool, version: Int) -> String {
        let value = afterRead ? "read" : (timer.map { String(Int($0 * 1000)) } ?? "off")
        return "sdChanged:\(value):\(version)"
    }

    static func rule(from type: String) -> (timer: TimeInterval?, afterRead: Bool, version: Int)? {
        guard type.hasPrefix("sdChanged:") else { return nil }
        let parts = type.dropFirst("sdChanged:".count).split(separator: ":", omittingEmptySubsequences: false)
        let value = parts.first.map(String.init) ?? ""
        let version = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        if value == "read" { return (nil, true, version) }
        return (Int(value).flatMap(clamp(ms:)), false, version)
    }

    /// Bei gleicher Version gewinnt die größere Kennung — beide Seiten
    /// kommen so auf dieselbe Regel.
    static func adoptForeignRule(mine: Int, theirs: Int, myId: String, theirId: String) -> Bool {
        theirs != mine ? theirs > mine : myId.utf16.lexicographicallyPrecedes(theirId.utf16)
    }
}

/// Die Regeln der Kontaktanfragen — ContactRequestPolicy der Flutter-Fassung.
public enum ContactRequestPolicy {
    public static let maxOpenRequests = 20
    public static let maxDeclines = 3

    static func rejectIncoming(existing: Contact?, openIncoming: Int) -> Bool {
        if let existing {
            if existing.isBlocked { return true }
            if existing.requestState == .established { return false }
            if existing.declineCount >= maxDeclines { return true }
        }
        return openIncoming >= maxOpenRequests
    }

    static func stateAfterIncoming(_ existing: Contact?) -> RequestState {
        switch existing?.requestState {
        case nil, .incoming?, .declined?: .incoming
        case .outgoing?, .established?: .established
        }
    }

    static func afterLocalAdd(_ c: Contact) -> Contact {
        var c = c
        switch c.requestState {
        case .incoming: c.requestState = .established
        case .declined: c.requestState = .outgoing; c.declineCount = 0
        case .established, .outgoing: break
        }
        return c
    }
}

/// Der Inhalt eines Krypta-QR-Codes: {v, uid, ik, fp[, rt]}.
public struct QRPayload: Equatable, Sendable {
    public let userId: String
    public let publicKey: Data
    public let fingerprint: String
    public let requestToken: String?

    public enum ParseError: Error, Equatable {
        case invalidFormat, unsupportedVersion, fingerprintMismatch
    }

    public init(userId: String, publicKey: Data, requestToken: String?) {
        self.userId = userId
        self.publicKey = publicKey
        self.fingerprint = Contact.fullFingerprint(publicKey)
        self.requestToken = requestToken
    }

    public var encoded: String {
        var map: JSONObject = [
            "v": .int(requestToken == nil ? 1 : 2),
            "uid": .string(userId),
            "ik": .string(publicKey.base64),
            "fp": .string(fingerprint),
        ]
        if let requestToken { map["rt"] = .string(requestToken) }
        return (try? map.jsonString()) ?? ""
    }

    /// Streng wie QrPayloadPolicy: Obergrenzen, exakte Schlüssellänge,
    /// gültige Kennung — alles, bevor der Server befragt wird.
    public static func parse(_ raw: String) throws -> QRPayload {
        guard !raw.isEmpty, raw.count <= 2048, let map = try? JSONObject.parse(raw) else { throw ParseError.invalidFormat }
        guard case .int(let v)? = map["v"], v == 1 || v == 2 else { throw ParseError.unsupportedVersion }
        guard
            let uid = map["uid"]?.stringValue, let ik = map["ik"]?.stringValue, let fp = map["fp"]?.stringValue,
            [uid, ik, fp].allSatisfy({ !$0.isEmpty && $0.count <= 256 }),
            isValidUserId(uid),
            let key = Data(base64: ik), key.count == 32
        else { throw ParseError.invalidFormat }
        guard Contact.fullFingerprint(key) == fp else { throw ParseError.fingerprintMismatch }
        let rt = map["rt"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        return QRPayload(userId: uid, publicKey: key, requestToken: rt)
    }

    /// Kennung im Format von Firebase Auth.
    public static func isValidUserId(_ id: String) -> Bool {
        (10...128).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
