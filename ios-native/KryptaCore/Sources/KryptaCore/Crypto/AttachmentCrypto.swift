import Foundation

/// Verschlüsselung für Anhänge (Fotos, Videos, Sprachnachrichten, Dateien).
///
/// Jede Datei bekommt einen eigenen Zufallsschlüssel. Der verschlüsselte
/// Blob liegt auf dem Server unter einer zufälligen Kennung; Schlüssel und
/// SHA-256 des Blobs reisen in der Nachricht, also in der
/// Ende-zu-Ende-Verschlüsselung. Wer nur den Server sieht, hat eine
/// Zufallsdatei ohne Namen und ohne Absender.
///
/// Vor dem Verschlüsseln wird aufgefüllt (Padmé, wie bei PURBs): die Größe
/// verrät nur noch ungefähr, wie groß die Datei ist, bei höchstens 12 %
/// Mehraufwand.
///
/// Format: `[0x01][24 Nonce][16 MAC][Chiffrat]`, AAD `KryptaAttachment-v1`.
public enum AttachmentCrypto {
    /// Größte Datei vor dem Verschlüsseln.
    public static let maxSize = 25 * 1024 * 1024
    static let aad = "KryptaAttachment-v1".utf8Data
    static let headerLength = 1 + 24 + 16

    public struct Sealed: Sendable, Equatable {
        public let key: Data
        public let blob: Data
        /// SHA-256 des Blobs: der Empfänger prüft, dass er genau diesen bekam.
        public let digest: Data
    }

    public enum Failure: Error, Equatable {
        case tooLarge
        case digestMismatch
        case malformed
    }

    public static func seal(_ plaintext: Data) throws -> Sealed {
        guard !plaintext.isEmpty, plaintext.count <= maxSize else { throw Failure.tooLarge }
        let key = Data.random(count: 32)
        let box = try Primitives.xchachaSeal(pad(plaintext), key: key, aad: aad)
        let blob = Data([0x01]) + box.nonce + box.mac + box.ciphertext
        return Sealed(key: key, blob: blob, digest: Primitives.sha256(blob))
    }

    public static func open(_ blob: Data, key: Data, digest: Data) throws -> Data {
        guard blob.count <= maxBlobSize else { throw Failure.tooLarge }
        guard Primitives.sha256(blob).constantTimeEquals(digest) else { throw Failure.digestMismatch }
        let bytes = blob.detached
        guard bytes.count > headerLength, bytes[0] == 0x01 else { throw Failure.malformed }
        let padded = try Primitives.xchachaOpen(
            .init(ciphertext: bytes.subdata(in: headerLength..<bytes.count), nonce: bytes.subdata(in: 1..<25), mac: bytes.subdata(in: 25..<41)),
            key: key, aad: aad
        )
        return try unpad(padded)
    }

    /// Größter Blob, der aus einer erlaubten Datei entstehen kann.
    public static var maxBlobSize: Int { padme(maxSize + 4) + headerLength }

    // MARK: - Auffüllen

    /// Padmé: rundet auf, sodass nur die obersten Bits der Länge übrig bleiben.
    public static func padme(_ length: Int) -> Int {
        guard length > 1 else { return max(length, 1) }
        let e = Int.bitWidth - 1 - length.leadingZeroBitCount     // floor(log2 L)
        let s = Int.bitWidth - (e).leadingZeroBitCount            // floor(log2 E) + 1
        let lastBits = max(0, e - s)
        let mask = (1 << lastBits) - 1
        return (length + mask) & ~mask
    }

    static func pad(_ data: Data) -> Data {
        var out = Data.bigEndian(UInt32(data.count))
        out.append(data)
        out.append(Data(count: padme(out.count) - out.count))
        return out
    }

    static func unpad(_ padded: Data) throws -> Data {
        let bytes = [UInt8](padded.prefix(4))
        guard bytes.count == 4 else { throw Failure.malformed }
        let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard length > 0, 4 + length <= padded.count else { throw Failure.malformed }
        return padded.subdata(in: padded.startIndex + 4 ..< padded.startIndex + 4 + length)
    }
}
