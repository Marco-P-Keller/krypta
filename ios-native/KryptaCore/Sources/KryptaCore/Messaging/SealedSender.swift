import Foundation

/// Versiegelter Absender: wer schreibt, steht nur noch in der Verschlüsselung.
///
/// Früher lag neben jeder Nachricht `sid` im Klartext auf dem Server, und die
/// Regeln verlangten, dass es die angemeldete Kennung ist — Firebase wusste
/// bei jeder Nachricht, wer wem schreibt. Versiegelt geht die Nachricht ohne
/// Anmeldung hinaus, und Absender, Nachrichtenkennung und Ratchet-Nachricht
/// liegen zusammen in einem Umschlag, den nur die Empfängerin öffnet:
///
///     0x01 ‖ Ephemeral (32) ‖ Nonce (24) ‖ MAC (16) ‖ Chiffrat
///
/// Schlüssel: HKDF-SHA256(X25519(Ephemeral, Identität der Empfängerin),
/// salt: Ephemeral ‖ Identität, info: "KryptaSealed-v1"). Die AAD bindet den
/// Umschlag an die Kennung der Empfängerin, damit er nicht umgeleitet werden
/// kann.
///
/// Der Umschlag beweist nicht, wer ihn geschrieben hat — das tut die
/// Ratchet-Nachricht darin: nur der echte Kontakt hält die Sitzung, und `_sid`
/// in ihr muss zum Umschlag passen (Engine+Receive).
///
/// Wer schreiben darf, entscheidet der Zustellschlüssel: 32 Zufallsbytes, die
/// die Empfängerin ihren Kontakten verschlüsselt mitgibt (`_dk`) und von denen
/// der Server nur den SHA-256 kennt (`sealedAccess/{uid}`). Er ist für alle
/// Kontakte derselbe und verrät deshalb niemanden.
public enum SealedSender {
    public struct Contents: Equatable, Sendable {
        public let senderId: String
        public let messageId: String
        public let payload: JSONObject

        public init(senderId: String, messageId: String, payload: JSONObject) {
            self.senderId = senderId
            self.messageId = messageId
            self.payload = payload
        }
    }

    public static let accessKeyLength = 32
    /// Größer wird kein Umschlag: die Nutzlast ist auf 64 KiB begrenzt.
    public static let maxEnvelopeLength = 96 * 1024

    static let version: UInt8 = 1
    static let info = "KryptaSealed-v1".utf8Data
    static let headerLength = 1 + 32 + 24 + 16

    public static func seal(_ contents: Contents, recipientId: String, recipientIdentity: Data) throws -> Data {
        guard recipientIdentity.count == 32 else { throw CryptoError.invalidKeyLength }
        let map: JSONObject = [
            "sid": .string(contents.senderId),
            "mid": .string(contents.messageId),
            "p": .object(contents.payload),
        ]
        let plaintext = try map.jsonString().utf8Data

        var eph = KeyPair.generate()
        defer { eph.privateKey.zero() }
        var key = try deriveKey(privateKey: eph.privateKey, publicKey: recipientIdentity,
                                ephemeral: eph.publicKey, recipientIdentity: recipientIdentity)
        defer { key.zero() }
        let box = try Primitives.xchachaSeal(plaintext, key: key, aad: aad(recipientId))
        return Data([version]) + eph.publicKey + box.nonce + box.mac + box.ciphertext
    }

    public static func open(_ envelope: Data, recipientId: String, identity: KeyPair) throws -> Contents {
        let bytes = envelope.detached
        guard bytes.count > headerLength, bytes.count <= maxEnvelopeLength, bytes[0] == version else {
            throw CryptoError.malformed("sealed envelope")
        }
        let eph = bytes[1..<33].detached
        let nonce = bytes[33..<57].detached
        let mac = bytes[57..<73].detached
        let ciphertext = bytes[73...].detached

        var key = try deriveKey(privateKey: identity.privateKey, publicKey: eph,
                                ephemeral: eph, recipientIdentity: identity.publicKey)
        defer { key.zero() }
        let plaintext = try Primitives.xchachaOpen(
            .init(ciphertext: ciphertext, nonce: nonce, mac: mac), key: key, aad: aad(recipientId)
        )
        guard let map = try? JSONObject.parse(String(decoding: plaintext, as: UTF8.self)),
              let sid = map["sid"]?.stringValue, let mid = map["mid"]?.stringValue,
              let payload = map["p"]?.objectValue else {
            throw CryptoError.malformed("sealed contents")
        }
        return Contents(senderId: sid, messageId: mid, payload: payload)
    }

    /// Was der Server vom Zustellschlüssel kennt.
    public static func accessKeyHash(_ key: Data) -> Data { Primitives.sha256(key) }

    /// Beide Seiten rechnen dasselbe: der Absender mit seinem Ephemeral gegen
    /// die Identität, die Empfängerin mit ihrer Identität gegen das Ephemeral.
    private static func deriveKey(privateKey: Data, publicKey: Data, ephemeral: Data, recipientIdentity: Data) throws -> Data {
        var shared = try Primitives.dh(privateKey: privateKey, publicKey: publicKey)
        defer { shared.zero() }
        return Primitives.hkdfSHA256(ikm: shared, salt: ephemeral + recipientIdentity, info: info, length: 32)
    }

    private static func aad(_ recipientId: String) -> Data { "krypta-sealed-v1|\(recipientId)".utf8Data }
}
