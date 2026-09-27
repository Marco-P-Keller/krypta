import Foundation
import KryptaBitcoin
import KryptaCore
import KryptaWallet

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
    /// Sealed Sender: der Zustellschlüssel dieses Kontakts (`_dk`). Mit ihm
    /// gehen Nachrichten an ihn ohne Absender auf den Server.
    public var sealedKey: Data?
    /// Der Kontakt hat schon ML-KEM gezeigt (signiert im Bündel oder im
    /// Handschlag). Ab dann wird kein Handschlag ohne mehr angenommen.
    public var postQuantum: Bool?
    /// Aus einer Gruppe bekannt: wer ihn vorgestellt hat (Kennung).
    public var introducedBy: String?
    /// Bitcoin im Chat (`_btc`): Der Kontakt hat eine Wallet und nimmt
    /// Zahlungen an. `nil`: noch nichts gehört (oder Flutter-App).
    public var acceptsBitcoin: Bool?
    /// Seine aktuelle Empfangsadresse für mich, verschlüsselt mitgeschickt.
    public var bitcoinAddress: String?
    /// Das Netz dieser Adresse (`main`, `test4`, `signet`, `regtest`).
    public var bitcoinNetwork: String?

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
            // Neuer Schlüssel, neues Gerät: was wir über das alte wussten,
            // gilt nicht mehr. Ohne neuen Schlüssel (der Server hat nur ein
            // fremdes Bündel gezeigt) bleibt es — sonst ließe sich so der
            // Schutz vor Herabstufung abschalten.
            sealedKey = nil
            postQuantum = nil
            // Neues Gerät, womöglich neue Wallet: die alte Adresse nicht mehr benutzen.
            acceptsBitcoin = nil
            bitcoinAddress = nil
            bitcoinNetwork = nil
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
    /// Gruppen: `text` trägt den Namen, um den es geht (Mitglied, neuer Gruppenname).
    case groupCreated, groupJoined, groupMemberAdded, groupMemberRemoved, groupMemberLeft, groupRenamed, groupRemovedYou, groupLeft
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
    /// Eine Bitcoin-Zahlung (`_pay`); der Text ist dann die Notiz dazu.
    public var payment: ChatPayment?
    /// Antwort auf diese Nachricht (`_re`). Nur die Kennung reist mit: das
    /// Zitat kommt aus dem eigenen Verlauf und verschwindet mit dem Original.
    public var replyTo: String?
    /// Reaktionen, je Absender ein Emoji (`_rx`).
    public var reactions: [String: String]?
    /// Zuletzt bearbeitet (`_ed`).
    public var editedAt: Date?
    /// Ein Foto, Video, eine Sprachnachricht oder Datei (`_att`); der Text
    /// ist dann die Bildunterschrift.
    public var attachment: Attachment?
    /// Eine Bitte um Bitcoin (`_req`); der Text ist die Notiz dazu.
    public var paymentRequest: ChatPaymentRequest?

    public var isSystemEvent: Bool { systemEvent != nil }

    /// Reaktionen in fester Reihenfolge: eigene zuerst, dann nach Absender.
    public func sortedReactions(me: String) -> [(sender: String, emoji: String)] {
        (reactions ?? [:]).sorted { a, b in
            if a.key == me { return b.key != me }
            if b.key == me { return false }
            return a.key < b.key
        }.map { ($0.key, $0.value) }
    }
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

/// Eine Bitte um Bitcoin im Chat (`_req`: Betrag und Netz).
///
/// Die Adresse steht nicht darin: sie reist wie immer als `_btc` mit
/// derselben Nachricht, nur für diesen Kontakt. Bezahlt wird wie jede
/// Zahlung im Chat; die Zahlung nennt die Bitte (`_pay.rq`).
public struct ChatPaymentRequest: Codable, Equatable, Sendable {
    public let sats: Int64
    public let network: BitcoinNetwork
    /// Die Nachricht mit der Zahlung darauf. `nil`: offen.
    public var paidBy: String?

    public init(sats: Int64, network: BitcoinNetwork) {
        self.sats = sats
        self.network = network
    }

    public var isPaid: Bool { paidBy != nil }
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
    /// Stumm bis zu diesem Zeitpunkt (`distantFuture`: bis zum Einschalten).
    public var mutedUntil: Date?
    /// Angepinnt seit; oben in der Liste, in dieser Reihenfolge.
    public var pinnedAt: Date?
    /// Im Archiv statt in der Liste.
    public var archived: Bool?
    /// Gruppenchat: Mitglieder, Name, Version. `nil` bei Einzelchats.
    public var group: GroupInfo?
    /// Einzelchat nur als Träger der Sitzung (Mitglied einer Gruppe, mit dem
    /// man noch nie direkt geschrieben hat): nicht in der Liste.
    public var hidden: Bool?

    public init(id: String = UUID().uuidString.lowercased(), recipientId: String, name: String) {
        self.id = id
        self.recipientId = recipientId
        self.name = name
    }

    public var ruleIsEphemeral: Bool { timer != nil || deleteAfterRead }

    public var isGroup: Bool { group != nil }
    public var isHidden: Bool { hidden == true }

    public func isMuted(at now: Date = Date()) -> Bool { mutedUntil.map { $0 > now } ?? false }
    public var isPinned: Bool { pinnedAt != nil }
    public var isArchived: Bool { archived == true }
}

/// Eine Gruppe: jede Nachricht geht einzeln über die Sitzung mit jedem
/// Mitglied (Engine+Groups). Den Stand bestimmt die Verwalterin; wer die
/// höhere Version hat, gilt.
public struct GroupInfo: Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    /// Kennungen, die eigene eingeschlossen.
    public var members: [String]
    public var admin: String
    public var version: Int
    /// Zufall der Gruppe: daraus der Schlüssel für Mitteilungs-Anhänger.
    public var secret: Data
    /// Die Schlüssel der Mitglieder, wie die Verwalterin sie angekündigt hat.
    public var keys: [String: Data]
    /// Ich bin nicht mehr dabei (ausgetreten oder entfernt): nur noch lesen.
    public var left: Bool?
    /// Mitglieder, bei denen der aktuelle Stand noch nicht angekommen ist
    /// (nur bei der Verwalterin). Beim nächsten Start geht er erneut hinaus.
    public var unsynced: [String]?

    public init(id: String, name: String, members: [String], admin: String, version: Int, secret: Data, keys: [String: Data]) {
        self.id = id
        self.name = name
        self.members = members
        self.admin = admin
        self.version = version
        self.secret = secret
        self.keys = keys
    }

    public var hasLeft: Bool { left == true }
    public func isAdmin(_ uid: String) -> Bool { admin == uid }
}

public enum AttachmentKind: String, Codable, Sendable {
    case image, video, audio, file
}

public enum AttachmentState: String, Codable, Sendable {
    /// Wird hochgeladen (Absender) oder geholt (Empfänger).
    case transferring
    /// Liegt verschlüsselt im Tresor dieses Geräts.
    case ready
    /// Holen ist gescheitert; erneut versuchen geht, solange der Server ihn hat.
    case failed
    /// Einmal angesehen oder abgelaufen: weg.
    case gone
}

/// Ein Anhang: wo der verschlüsselte Blob liegt, der Schlüssel dazu und was
/// die Oberfläche vor dem Laden zeigen kann. Der Inhalt selbst liegt im
/// Tresor (Slot `att.<id>`), nie im Klartext auf der Platte.
public struct Attachment: Codable, Equatable, Sendable {
    public let id: String
    public let key: Data
    public let digest: Data
    public let size: Int
    public let kind: AttachmentKind
    public let mime: String
    public var name: String?
    public var width: Int?
    public var height: Int?
    public var duration: Double?
    /// Kleines JPEG ohne Metadaten, reist in der Nachricht mit.
    public var thumbnail: Data?
    public var state: AttachmentState

    public init(id: String, key: Data, digest: Data, size: Int, kind: AttachmentKind, mime: String, name: String? = nil,
                width: Int? = nil, height: Int? = nil, duration: Double? = nil, thumbnail: Data? = nil, state: AttachmentState) {
        self.id = id
        self.key = key
        self.digest = digest
        self.size = size
        self.kind = kind
        self.mime = mime
        self.name = name
        self.width = width
        self.height = height
        self.duration = duration
        self.thumbnail = thumbnail
        self.state = state
    }

    public var slot: String { "att.\(id)" }
}

/// Was die App über eine Datei weiß, bevor sie verschickt wird.
public struct OutgoingAttachment: Sendable {
    public var data: Data
    public var kind: AttachmentKind
    public var mime: String
    public var name: String?
    public var width: Int?
    public var height: Int?
    public var duration: Double?
    public var thumbnail: Data?

    public init(data: Data, kind: AttachmentKind, mime: String, name: String? = nil, width: Int? = nil, height: Int? = nil,
                duration: Double? = nil, thumbnail: Data? = nil) {
        self.data = data
        self.kind = kind
        self.mime = mime
        self.name = name
        self.width = width
        self.height = height
        self.duration = duration
        self.thumbnail = thumbnail
    }
}

/// Eine Chat-Regel zum Auswählen: aus, Frist oder nach dem Lesen.
public enum ChatRuleChoice: Equatable, Sendable {
    case off
    case timer(TimeInterval)
    case afterRead
}

/// Ein Treffer der Suche in den Nachrichten.
public struct SearchHit: Identifiable, Equatable, Sendable {
    public let chatId: String
    public let messageId: String
    public let text: String
    public let timestamp: Date
    public let mine: Bool
    public var id: String { "\(chatId)|\(messageId)" }
}

/// Wie eine einzelne Nachricht gehen soll.
public struct SendOptions: Equatable, Sendable {
    public var selfDestruct: TimeInterval?
    public var fromChatRule = false
    public var burnAfterRead = false
    public var oneTime = false
    public var password: String?
    /// Antwort auf diese Nachricht.
    public var replyTo: String?

    public init(selfDestruct: TimeInterval? = nil, fromChatRule: Bool = false, burnAfterRead: Bool = false, oneTime: Bool = false, password: String? = nil, replyTo: String? = nil) {
        self.selfDestruct = selfDestruct
        self.fromChatRule = fromChatRule
        self.burnAfterRead = burnAfterRead
        self.oneTime = oneTime
        self.password = password
        self.replyTo = replyTo
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

/// Der Inhalt eines Krypta-QR-Codes: {v, uid, ik, fp[, rt][, dk]}.
///
/// `dk` ist der Zustellschlüssel: Wer den Code scannt, kann schon die Anfrage
/// versiegelt schicken, und Firebase sieht nicht, wer sich mit wem verbindet.
/// Die Flutter-Fassung liest das Feld nicht.
public struct QRPayload: Equatable, Sendable {
    public let userId: String
    public let publicKey: Data
    public let fingerprint: String
    public let requestToken: String?
    public let accessKey: Data?

    public enum ParseError: Error, Equatable {
        case invalidFormat, unsupportedVersion, fingerprintMismatch
    }

    public init(userId: String, publicKey: Data, requestToken: String?, accessKey: Data? = nil) {
        self.userId = userId
        self.publicKey = publicKey
        self.fingerprint = Contact.fullFingerprint(publicKey)
        self.requestToken = requestToken
        self.accessKey = accessKey
    }

    public var encoded: String {
        var map: JSONObject = [
            "v": .int(requestToken == nil ? 1 : 2),
            "uid": .string(userId),
            "ik": .string(publicKey.base64),
            "fp": .string(fingerprint),
        ]
        if let requestToken { map["rt"] = .string(requestToken) }
        if let accessKey { map["dk"] = .string(accessKey.base64) }
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
        var dk: Data?
        if let raw = map["dk"] {
            guard let b64 = raw.stringValue, let key = Data(base64: b64), key.count == SealedSender.accessKeyLength else {
                throw ParseError.invalidFormat
            }
            dk = key
        }
        return QRPayload(userId: uid, publicKey: key, requestToken: rt, accessKey: dk)
    }

    /// Kennung im Format von Firebase Auth.
    public static func isValidUserId(_ id: String) -> Bool {
        (10...128).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
