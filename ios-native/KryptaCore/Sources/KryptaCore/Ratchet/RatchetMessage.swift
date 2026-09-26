import Foundation

/// Kopf einer Ratchet-Nachricht: unverschlüsselt übertragen, aber Teil der AAD.
public struct RatchetHeader: Equatable, Sendable {
    public let dhPublicKey: Data
    public let messageNumber: Int
    public let previousChainLength: Int

    public init(dhPublicKey: Data, messageNumber: Int, previousChainLength: Int) {
        self.dhPublicKey = dhPublicKey.detached
        self.messageNumber = messageNumber
        self.previousChainLength = previousChainLength
    }

    /// Bytes für die AAD. Exakt der Text, den Dart von Hand zusammensetzt:
    /// `{"dh":"<b64>","n":N,"pn":PN}` — kein Leerzeichen, diese Reihenfolge.
    /// Ein anderer Serialisierer würde die Authentifizierung brechen.
    public var aadBytes: Data {
        "{\"dh\":\"\(dhPublicKey.base64)\",\"n\":\(messageNumber),\"pn\":\(previousChainLength)}".utf8Data
    }
}

public struct EncryptedRatchetMessage: Equatable, Sendable {
    public let ciphertext: Data
    public let nonce: Data
    public let mac: Data
}

/// Kopf und Chiffrat, so wie sie in `messages/{uid}/inbox/*.p` liegen.
public struct RatchetMessage: Equatable, Sendable {
    public let header: RatchetHeader
    public let ciphertext: EncryptedRatchetMessage

    /// Die Felder für Firestore (`v` setzt der Aufrufer, wie in Dart).
    public var payloadMap: JSONObject {
        [
            "v": 2,
            "dh": .string(header.dhPublicKey.base64),
            "n": .int(header.messageNumber),
            "pn": .int(header.previousChainLength),
            "c": .string(ciphertext.ciphertext.base64),
            "nc": .string(ciphertext.nonce.base64),
            "m": .string(ciphertext.mac.base64),
        ]
    }

    public init(header: RatchetHeader, ciphertext: EncryptedRatchetMessage) {
        self.header = header
        self.ciphertext = ciphertext
    }

    /// Liest die Felder aus einer fremden Nachricht. Alles ist Eingabe von
    /// außen: ein falscher Typ ist ein Fehler, kein Absturz.
    public init(payload: JSONObject) throws {
        guard
            let dh = payload["dh"]?.stringValue.flatMap(Data.init(base64:)),
            let n = payload["n"]?.intValue,
            let pn = payload["pn"]?.intValue,
            let c = payload["c"]?.stringValue.flatMap(Data.init(base64:)),
            let nc = payload["nc"]?.stringValue.flatMap(Data.init(base64:)),
            let m = payload["m"]?.stringValue.flatMap(Data.init(base64:))
        else { throw CryptoError.malformed("ratchet payload") }
        header = RatchetHeader(dhPublicKey: dh, messageNumber: n, previousChainLength: pn)
        ciphertext = EncryptedRatchetMessage(ciphertext: c, nonce: nc, mac: m)
    }
}
