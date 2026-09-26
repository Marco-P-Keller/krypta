import Foundation

/// Padding, Passwort-Nachrichten und lokale Verschlüsselung —
/// die Teile von encryption_service.dart, die auf dem Draht oder auf der
/// Platte landen.
public enum Envelope {
    // MARK: Padding

    /// Auf die nächste Zweierpotenz (mindestens 256 Byte) auffüllen:
    /// [4 Byte Länge BE][Text][Zufall].
    public static func pad(_ plaintext: Data) -> Data {
        var block = 256
        while block < plaintext.count + 4 { block *= 2 }
        var out = Data.bigEndian(UInt32(plaintext.count))
        out.append(plaintext)
        out.append(Data.random(count: block - out.count))
        return out
    }

    public static func unpad(_ padded: Data) throws -> Data {
        let bytes = [UInt8](padded)
        guard bytes.count >= 4 else { throw CryptoError.malformed("padding") }
        let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard 4 + length <= bytes.count else { throw CryptoError.malformed("padding") }
        return Data(bytes[4..<(4 + length)])
    }

    // MARK: Passwortgeschützte Nachrichten

    /// Argon2id → XChaCha20-Poly1305, als Base64 eines JSON-Objekts
    /// {v, s, n, m, c}. Mit AAD entsteht v3 (an Absender, Empfänger und
    /// Nachricht gebunden), ohne v2.
    public static func encryptWithPassword(_ plaintext: String, password: String, aad: String?) throws -> String {
        let salt = Data.random(count: 16)
        var key = try Primitives.argon2id(password: password.utf8Data, salt: salt)
        defer { key.zero() }
        let box = try Primitives.xchachaSeal(plaintext.utf8Data, key: key, aad: aad?.utf8Data ?? Data())
        let payload: JSONObject = [
            "v": .int(aad == nil ? 2 : 3),
            "s": .string(salt.base64),
            "n": .string(box.nonce.base64),
            "m": .string(box.mac.base64),
            "c": .string(box.ciphertext.base64),
        ]
        return try payload.jsonString().utf8Data.base64
    }

    /// `nil` bei falschem Passwort oder beschädigten Daten.
    public static func decryptWithPassword(_ blob: String, password: String, aad: String?) -> String? {
        guard
            let raw = Data(base64: blob),
            let map = try? JSONObject.parse(String(decoding: raw, as: UTF8.self)),
            let salt = map["s"]?.stringValue.flatMap(Data.init(base64:)),
            let nonce = map["n"]?.stringValue.flatMap(Data.init(base64:)),
            let mac = map["m"]?.stringValue.flatMap(Data.init(base64:)),
            let ct = map["c"]?.stringValue.flatMap(Data.init(base64:))
        else { return nil }
        let version = map["v"]?.intValue ?? 1
        if version < 2 { return nil }
        if version >= 3 && aad == nil { return nil }
        let aadBytes = version >= 3 ? (aad ?? "").utf8Data : Data()
        guard var key = try? Primitives.argon2id(password: password.utf8Data, salt: salt) else { return nil }
        defer { key.zero() }
        guard let plain = try? Primitives.xchachaOpen(.init(ciphertext: ct, nonce: nonce, mac: mac), key: key, aad: aadBytes) else {
            return nil
        }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: Lokale Verschlüsselung

    /// Format v2 der Flutter-Fassung: [0x02][24 Nonce][16 MAC][Chiffrat],
    /// AAD = Speicherplatz. Bindet jeden Blob an seinen Platz, sodass zwei
    /// Dateien nicht vertauscht werden können.
    public static func sealLocal(_ plaintext: Data, key: Data, slot: String) throws -> Data {
        let box = try Primitives.xchachaSeal(plaintext, key: key, aad: slot.utf8Data)
        return Data([0x02]) + box.nonce + box.mac + box.ciphertext
    }

    public static func openLocal(_ blob: Data, key: Data, slot: String) throws -> Data {
        let bytes = blob.detached
        guard bytes.count >= 41, bytes[0] == 0x02 else { throw CryptoError.malformed("local blob") }
        return try Primitives.xchachaOpen(
            .init(ciphertext: bytes.subdata(in: 41..<bytes.count), nonce: bytes.subdata(in: 1..<25), mac: bytes.subdata(in: 25..<41)),
            key: key, aad: slot.utf8Data
        )
    }
}
