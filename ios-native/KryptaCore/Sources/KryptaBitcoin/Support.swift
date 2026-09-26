import Foundation
#if canImport(Security)
import Security
#endif

/// Fehler der Bitcoin-Schicht. Knapp wie in KryptaCore: nach außen zählt,
/// *dass* etwas nicht stimmt.
public enum BitcoinError: Error, Equatable, Sendable {
    case invalidKey
    case invalidSeed
    case derivationFailed
    case invalidEncoding(String)
    case invalidAddress
    case wrongNetwork
    case unsupportedAddress
    case invalidTransaction(String)
    case signingFailed
    case invalidMnemonic
}

/// Zufall aus dem System. Auf Apple-Geräten SecRandomCopyBytes wie überall
/// in Krypta; unter Linux (nur Tests) der Zufall der Standardbibliothek,
/// der dort aus getrandom kommt.
public enum SecureRandom {
    public static func bytes(_ count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        guard count > 0 else { return out }
        #if canImport(Security)
        let status = out.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "SecRandomCopyBytes fehlgeschlagen")
        #else
        var rng = SystemRandomNumberGenerator()
        for i in 0..<count { out[i] = rng.next() }
        #endif
        return out
    }
}

/// Geheime Bytes, die beim Freigeben überschrieben werden. Best effort:
/// Swift kann beim Kopieren Spuren hinterlassen, wie in KryptaCore auch.
/// Wer die Bytes braucht, borgt sie sich mit `withBytes` und kopiert sie
/// nicht in langlebige Werte.
public final class SecretBytes: @unchecked Sendable {
    private var storage: [UInt8]

    public init(_ bytes: [UInt8]) { storage = bytes }
    public convenience init(_ data: Data) { self.init([UInt8](data)) }

    deinit { storage.wipe() }

    public var count: Int { storage.count }

    public func withBytes<T>(_ body: ([UInt8]) throws -> T) rethrows -> T {
        try body(storage)
    }

    /// Nur für Tests und die Sicherung der Wörter.
    public var copy: [UInt8] { storage }
}

public extension Array where Element == UInt8 {
    /// Überschreibt den Inhalt mit Nullen.
    mutating func wipe() {
        withUnsafeMutableBufferPointer { buffer in
            for i in buffer.indices { buffer[i] = 0 }
        }
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = Self.nibble(chars[i]), let lo = Self.nibble(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        self = out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): c - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}

public extension Data {
    var hex: String { [UInt8](self).hex }

    init?(hex: String) {
        guard let bytes = [UInt8](hex: hex) else { return nil }
        self.init(bytes)
    }
}

/// Little-Endian-Hilfen für das Bitcoin-Format.
extension Array where Element == UInt8 {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    /// CompactSize, wie Bitcoin Längen schreibt.
    mutating func appendVarInt(_ value: UInt64) {
        switch value {
        case 0..<0xFD: append(UInt8(value))
        case 0xFD...0xFFFF: append(0xFD); appendLE(UInt16(value))
        case 0x10000...0xFFFF_FFFF: append(0xFE); appendLE(UInt32(value))
        default: append(0xFF); appendLE(value)
        }
    }

    mutating func appendVarBytes(_ bytes: [UInt8]) {
        appendVarInt(UInt64(bytes.count))
        append(contentsOf: bytes)
    }

    static func varIntSize(_ value: Int) -> Int {
        switch value {
        case ..<0xFD: 1
        case ...0xFFFF: 3
        case ...0xFFFF_FFFF: 5
        default: 9
        }
    }
}

/// Liest Bitcoin-Binärformat mit Grenzprüfung bei jedem Schritt. Wirft statt
/// abzustürzen: die Bytes kommen aus dem Netz.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { offset == bytes.count }

    mutating func read(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= remaining else { throw BitcoinError.invalidTransaction("zu kurz") }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func readByte() throws -> UInt8 { try read(1)[0] }

    mutating func readLE<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let raw = try read(MemoryLayout<T>.size)
        var value: T = 0
        for (i, b) in raw.enumerated() { value |= T(b) << (8 * i) }
        return value
    }

    /// CompactSize, nur in kanonischer Form (wie Bitcoin Core).
    mutating func readVarInt() throws -> UInt64 {
        let first = try readByte()
        switch first {
        case 0xFD:
            let v = UInt64(try readLE(UInt16.self))
            guard v >= 0xFD else { throw BitcoinError.invalidTransaction("CompactSize") }
            return v
        case 0xFE:
            let v = UInt64(try readLE(UInt32.self))
            guard v > 0xFFFF else { throw BitcoinError.invalidTransaction("CompactSize") }
            return v
        case 0xFF:
            let v = try readLE(UInt64.self)
            guard v > 0xFFFF_FFFF else { throw BitcoinError.invalidTransaction("CompactSize") }
            return v
        default:
            return UInt64(first)
        }
    }

    /// Länge plus Bytes; die Länge darf nicht über das Ende zeigen.
    mutating func readVarBytes() throws -> [UInt8] {
        let n = try readVarInt()
        guard n <= UInt64(remaining) else { throw BitcoinError.invalidTransaction("Länge") }
        return try read(Int(n))
    }
}
