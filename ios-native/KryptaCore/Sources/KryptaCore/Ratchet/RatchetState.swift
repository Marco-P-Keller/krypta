import Foundation

/// Zustand einer Double-Ratchet-Sitzung für einen Chat.
///
/// Ein Werttyp: jede Änderung erzeugt einen neuen Zustand, der alte bleibt
/// unberührt. Das ist der Grund, warum ein gefälschter Kopf, der bis zur
/// MAC-Prüfung durchkommt, die laufende Sitzung nicht beschädigen kann.
public struct RatchetState: Equatable, Sendable {
    public static let currentProtocolVersion = 1

    public var protocolVersion = RatchetState.currentProtocolVersion
    public var rootKey: Data
    public var sendingChainKey: Data?
    public var receivingChainKey: Data?
    public var dhSendingPublic: Data
    public var dhSendingPrivate: Data
    public var dhReceivingPublic: Data?
    public var sendMessageNumber = 0
    public var receiveMessageNumber = 0
    public var previousChainLength = 0
    /// "base64(dhPub):n" → Nachrichtenschlüssel für überholte Nachrichten.
    public var skippedMessageKeys: [String: Data] = [:]
    public var skippedKeyTimestamps: [String: Int] = [:]
    public var sessionId: String?
    public var previousSessionId: String?
    public var createdAt = Date()
    /// Laufende Nummer jeder gesendeten Nachricht (`_seq`), gegen Wiedereinspielen.
    public var globalSendSeqNo = 0
    public var highestRecvSeq = -1
    public var recentRecvSeqs: Set<Int> = []
    public var peerSeenPsids: Set<String> = []

    public init(
        rootKey: Data,
        sendingChainKey: Data? = nil,
        receivingChainKey: Data? = nil,
        dhSendingPublic: Data,
        dhSendingPrivate: Data,
        dhReceivingPublic: Data? = nil
    ) {
        self.rootKey = rootKey.detached
        self.sendingChainKey = sendingChainKey?.detached
        self.receivingChainKey = receivingChainKey?.detached
        self.dhSendingPublic = dhSendingPublic.detached
        self.dhSendingPrivate = dhSendingPrivate.detached
        self.dhReceivingPublic = dhReceivingPublic?.detached
    }

    // MARK: Speicherformat — dieselben Schlüssel wie RatchetState.toMap in Dart

    public var json: JSONObject {
        var map: JSONObject = [
            "pv": .int(protocolVersion),
            "rk": .string(rootKey.base64),
            "cks": sendingChainKey.map { .string($0.base64) } ?? .null,
            "ckr": receivingChainKey.map { .string($0.base64) } ?? .null,
            "dhsp": .string(dhSendingPublic.base64),
            "dhsk": .string(dhSendingPrivate.base64),
            "dhrp": dhReceivingPublic.map { .string($0.base64) } ?? .null,
            "ns": .int(sendMessageNumber),
            "nr": .int(receiveMessageNumber),
            "pn": .int(previousChainLength),
            "skip": .object(skippedMessageKeys.mapValues { .string($0.base64) }),
            "ca": .int(Int(createdAt.timeIntervalSince1970 * 1000)),
            "gsn": .int(globalSendSeqNo),
            "hrs": .int(highestRecvSeq),
        ]
        if !skippedKeyTimestamps.isEmpty { map["skipTs"] = .object(skippedKeyTimestamps.mapValues { .int($0) }) }
        if let sessionId { map["sid"] = .string(sessionId) }
        if let previousSessionId { map["psid"] = .string(previousSessionId) }
        if !recentRecvSeqs.isEmpty { map["rrs"] = .array(recentRecvSeqs.sorted().map { .int($0) }) }
        if !peerSeenPsids.isEmpty { map["psp"] = .array(peerSeenPsids.sorted().map { .string($0) }) }
        return map
    }

    public init(json map: JSONObject) throws {
        func bytes(_ key: String) throws -> Data {
            guard let d = map[key]?.stringValue.flatMap(Data.init(base64:)) else {
                throw CryptoError.malformed("ratchet state \(key)")
            }
            return d
        }
        func optionalBytes(_ key: String) -> Data? { map[key]?.stringValue.flatMap(Data.init(base64:)) }

        self.init(
            rootKey: try bytes("rk"),
            sendingChainKey: optionalBytes("cks"),
            receivingChainKey: optionalBytes("ckr"),
            dhSendingPublic: try bytes("dhsp"),
            dhSendingPrivate: try bytes("dhsk"),
            dhReceivingPublic: optionalBytes("dhrp")
        )
        protocolVersion = map["pv"]?.intValue ?? 1
        sendMessageNumber = map["ns"]?.intValue ?? 0
        receiveMessageNumber = map["nr"]?.intValue ?? 0
        previousChainLength = map["pn"]?.intValue ?? 0
        skippedMessageKeys = (map["skip"]?.objectValue ?? [:]).compactMapValues { $0.stringValue.flatMap(Data.init(base64:)) }
        skippedKeyTimestamps = (map["skipTs"]?.objectValue ?? [:]).compactMapValues(\.intValue)
        sessionId = map["sid"]?.stringValue
        previousSessionId = map["psid"]?.stringValue
        if let ms = map["ca"]?.intValue { createdAt = Date(timeIntervalSince1970: Double(ms) / 1000) }
        globalSendSeqNo = map["gsn"]?.intValue ?? 0
        highestRecvSeq = map["hrs"]?.intValue ?? ((map["grn"]?.intValue ?? 0) - 1)
        if let rrs = map["rrs"]?.arrayValue {
            recentRecvSeqs = Set(rrs.compactMap(\.intValue))
        } else if let grn = map["grn"]?.intValue, grn > 0 {
            // Wie _seedLegacyRecvWindow in Dart.
            recentRecvSeqs = Set(max(0, grn - 200)..<grn)
        }
        peerSeenPsids = Set((map["psp"]?.arrayValue ?? []).compactMap(\.stringValue))
    }
}
