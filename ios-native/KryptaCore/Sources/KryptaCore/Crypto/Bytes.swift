import Foundation
import Security

/// Hilfen für Byte-Folgen, die überall im Protokoll gebraucht werden.
public extension Data {
    /// Standard-Base64 mit Auffüllung, wie Darts `base64Encode`.
    var base64: String { base64EncodedString() }

    /// Liest Standard-Base64. Wie in Dart wird nichts stillschweigend
    /// repariert: fehlerhafte Eingaben ergeben `nil`.
    init?(base64 string: String) {
        self.init(base64Encoded: string)
    }

    /// `count` Bytes aus dem System-Zufall.
    static func random(count: Int) -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes fehlgeschlagen")
        return bytes
    }

    /// Vergleich in konstanter Zeit — für alles, was geheim ist.
    func constantTimeEquals(_ other: Data) -> Bool {
        guard count == other.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<count {
            diff |= self[startIndex + i] ^ other[other.startIndex + i]
        }
        return diff == 0
    }

    var isAllZero: Bool { allSatisfy { $0 == 0 } }

    /// Überschreibt den Inhalt mit Nullen. Best effort: Swift kann beim
    /// Kopieren Spuren hinterlassen haben, wie Dart auch.
    mutating func zero() {
        resetBytes(in: startIndex..<endIndex)
    }

    /// Big-Endian-Darstellung, wie sie im Transparenzprotokoll steht.
    static func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        Swift.withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    /// Eine Kopie mit eigenem Speicher und Startindex 0. Slices von `Data`
    /// behalten den Index des Originals; nach außen geben wir nur
    /// Kopien, damit niemand daran stolpert.
    var detached: Data { Data(self) }
}

public extension String {
    var utf8Data: Data { Data(utf8) }
}
