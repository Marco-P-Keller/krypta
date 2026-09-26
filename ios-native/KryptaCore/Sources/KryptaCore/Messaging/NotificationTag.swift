import Foundation

/// Woran das iPhone der Empfängerin erkennt, von wem eine Mitteilung kommt —
/// ohne dass Apple, Google oder Firebase es erfahren.
///
/// Der Absender legt in die Nachricht (`p.nt`) einen Anhänger aus acht
/// Zufallsbytes und einer HMAC darüber. Der Schlüssel entsteht aus der
/// Diffie-Hellman-Rechnung der beiden Identitäten; nur die zwei Beteiligten
/// kennen ihn. Die Cloud Function reicht den Anhänger unverändert in die
/// Push-Mitteilung weiter, und die Notification Service Extension probiert
/// ihn gegen die Schlüssel der eigenen Kontakte. Wer mitliest, sieht eine
/// Zufallszahl, die sich bei jeder Nachricht ändert.
///
/// Drei Fälle:
/// - Nachricht: Anhänger mit dem Paarschlüssel → „Neue Nachricht von …"
/// - Kontaktanfrage: Anhänger mit einem Schlüssel aus der Identität der
///   Empfängerin (sie kennt den Absender ja noch nicht) → „Neue Kontaktanfrage"
/// - Steuernachricht (Zustellung, gelesen …): leerer Anhänger → keine Mitteilung
public enum NotificationTag {
    /// Leerer Anhänger: die Cloud Function schickt keine Mitteilung.
    public static let quiet = ""

    static let nonceLength = 8
    static let macLength = 12

    public static func pairKey(identity: KeyPair, peerIdentityPublicKey: Data, ownId: String, peerId: String) throws -> Data {
        var shared = try Primitives.dh(privateKey: identity.privateKey, publicKey: peerIdentityPublicKey)
        defer { shared.zero() }
        let ids = [ownId, peerId].sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }.joined(separator: "|")
        return Primitives.hkdfSHA256(ikm: shared, salt: Data(count: 32), info: "KryptaNotify-v1|\(ids)".utf8Data, length: 32)
    }

    /// Für Anfragen: beide Seiten kennen den öffentlichen Schlüssel der
    /// Empfängerin. Gegen Apple und Google reicht das; Firebase kennt den
    /// Schlüssel zwar, sieht aber an der ersten Nachricht von einer neuen
    /// Kennung ohnehin, dass eine Verbindung entsteht.
    public static func requestKey(recipientIdentityPublicKey: Data) -> Data {
        Primitives.hkdfSHA256(ikm: recipientIdentityPublicKey, salt: Data(count: 32), info: "KryptaNotifyRequest-v1".utf8Data, length: 32)
    }

    public static func make(key: Data) -> String {
        let nonce = Data.random(count: nonceLength)
        return (nonce + mac(key: key, nonce: nonce)).base64
    }

    public static func matches(_ tag: String, key: Data) -> Bool {
        guard let raw = Data(base64: tag), raw.count == nonceLength + macLength else { return false }
        let nonce = raw.prefix(nonceLength).detached
        return mac(key: key, nonce: nonce).constantTimeEquals(raw.suffix(macLength).detached)
    }

    private static func mac(key: Data, nonce: Data) -> Data {
        Primitives.hmacSHA256(key: key, message: "nt|".utf8Data + nonce).prefix(macLength).detached
    }
}

/// Was die Notification Service Extension braucht, um einen Anhänger einem
/// Namen zuzuordnen. Die App legt es in den geteilten Schlüsselbund.
public struct NotificationIndex: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var key: Data
        public var name: String?

        public init(key: Data, name: String?) {
            self.key = key
            self.name = name
        }
    }

    public var entries: [Entry]
    public var requestKey: Data?
    /// Namen zeigen oder nur „Neue Nachricht".
    public var showNames: Bool

    public init(entries: [Entry], requestKey: Data?, showNames: Bool) {
        self.entries = entries
        self.requestKey = requestKey
        self.showNames = showNames
    }

    public enum Match: Equatable, Sendable {
        case contact(name: String?)
        case request
        case unknown
    }

    public func resolve(_ tag: String?) -> Match {
        guard let tag, !tag.isEmpty else { return .unknown }
        if let hit = entries.first(where: { NotificationTag.matches(tag, key: $0.key) }) {
            return .contact(name: showNames ? hit.name : nil)
        }
        if let requestKey, NotificationTag.matches(tag, key: requestKey) { return .request }
        return .unknown
    }
}
