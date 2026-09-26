import Foundation

/// Base58Check: alte Adressen (1…, 3…) und erweiterte Schlüssel (xpub…).
public enum Base58 {
    static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    static let decodeMap: [Int8] = {
        var map = [Int8](repeating: -1, count: 128)
        for (i, c) in alphabet.enumerated() { map[Int(c)] = Int8(i) }
        return map
    }()

    public static func encode(_ bytes: [UInt8]) -> String {
        let zeros = bytes.prefix { $0 == 0 }.count
        var digits = [UInt8]()
        for byte in bytes {
            var carry = Int(byte)
            for i in 0..<digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        let prefix = String(repeating: "1", count: zeros)
        return prefix + String(decoding: digits.reversed().map { alphabet[Int($0)] }, as: UTF8.self)
    }

    public static func decode(_ string: String) -> [UInt8]? {
        let chars = Array(string.utf8)
        guard chars.count <= 256 else { return nil }
        let zeros = chars.prefix { $0 == UInt8(ascii: "1") }.count
        var bytes = [UInt8]()
        for c in chars {
            guard c < 128, decodeMap[Int(c)] >= 0 else { return nil }
            var carry = Int(decodeMap[Int(c)])
            for i in 0..<bytes.count {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        return [UInt8](repeating: 0, count: zeros) + bytes.reversed()
    }

    public static func encodeCheck(_ payload: [UInt8]) -> String {
        encode(payload + Hashes.hash256(payload).prefix(4))
    }

    public static func decodeCheck(_ string: String) -> [UInt8]? {
        guard let raw = decode(string), raw.count >= 4 else { return nil }
        let payload = Array(raw.dropLast(4))
        guard Array(Hashes.hash256(payload).prefix(4)) == Array(raw.suffix(4)) else { return nil }
        return payload
    }
}

/// Bech32 (BIP173) und Bech32m (BIP350).
public enum Bech32 {
    public enum Variant: Sendable { case bech32, bech32m }

    static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
    static let generator: [UInt32] = [0x3B6A_57B2, 0x2650_8E6D, 0x1EA1_19FA, 0x3D42_33DD, 0x2A14_62B3]

    static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = (chk & 0x1FF_FFFF) << 5 ^ UInt32(v)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 { chk ^= generator[i] }
        }
        return chk
    }

    static func expand(_ hrp: [UInt8]) -> [UInt8] {
        hrp.map { $0 >> 5 } + [0] + hrp.map { $0 & 31 }
    }

    static func constant(_ variant: Variant) -> UInt32 { variant == .bech32 ? 1 : 0x2BC8_30A3 }

    public static func encode(hrp: String, data: [UInt8], variant: Variant) -> String {
        let h = Array(hrp.lowercased().utf8)
        let mod = polymod(expand(h) + data + [0, 0, 0, 0, 0, 0]) ^ constant(variant)
        let checksum = (0..<6).map { UInt8((mod >> UInt32(5 * (5 - $0))) & 31) }
        return hrp.lowercased() + "1" + String(decoding: (data + checksum).map { charset[Int($0)] }, as: UTF8.self)
    }

    /// Streng nach BIP173: höchstens 90 Zeichen, nicht gemischt groß/klein,
    /// nur druckbares ASCII im Präfix.
    public static func decode(_ string: String) -> (hrp: String, data: [UInt8], variant: Variant)? {
        let chars = Array(string.utf8)
        guard chars.count >= 8, chars.count <= 90 else { return nil }
        guard chars.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { return nil }
        let hasLower = chars.contains { $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z") }
        let hasUpper = chars.contains { $0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z") }
        guard !(hasLower && hasUpper) else { return nil }
        let lower = chars.map { $0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z") ? $0 + 32 : $0 }
        guard let sep = lower.lastIndex(of: UInt8(ascii: "1")), sep >= 1, sep + 7 <= lower.count else { return nil }
        let hrp = Array(lower[..<sep])
        var data = [UInt8]()
        for c in lower[(sep + 1)...] {
            guard let v = charset.firstIndex(of: c) else { return nil }
            data.append(UInt8(v))
        }
        let mod = polymod(expand(hrp) + data)
        let variant: Variant
        switch mod {
        case constant(.bech32): variant = .bech32
        case constant(.bech32m): variant = .bech32m
        default: return nil
        }
        return (String(decoding: hrp, as: UTF8.self), Array(data.dropLast(6)), variant)
    }

    /// Bits umgruppieren (8 → 5 und zurück).
    static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        var out = [UInt8]()
        let maxv = (1 << to) - 1
        for value in data {
            guard Int(value) >> from == 0 else { return nil }
            acc = (acc << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 { out.append(UInt8((acc << (to - bits)) & maxv)) }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            return nil
        }
        return out
    }
}

/// Segwit-Adressen: Version und Programm, geprüft nach BIP173/BIP350.
public enum SegwitAddress {
    public static func encode(hrp: String, version: Int, program: [UInt8]) -> String? {
        guard (0...16).contains(version), (2...40).contains(program.count) else { return nil }
        if version == 0, program.count != 20, program.count != 32 { return nil }
        guard let data = Bech32.convertBits(program, from: 8, to: 5, pad: true) else { return nil }
        return Bech32.encode(hrp: hrp, data: [UInt8(version)] + data, variant: version == 0 ? .bech32 : .bech32m)
    }

    public static func decode(hrp expected: String, _ address: String) -> (version: Int, program: [UInt8])? {
        guard let (hrp, data, variant) = Bech32.decode(address), hrp == expected, let first = data.first else { return nil }
        let version = Int(first)
        guard version <= 16 else { return nil }
        guard variant == (version == 0 ? .bech32 : .bech32m) else { return nil }
        guard let program = Bech32.convertBits(Array(data.dropFirst()), from: 5, to: 8, pad: false),
              (2...40).contains(program.count) else { return nil }
        if version == 0, program.count != 20, program.count != 32 { return nil }
        return (version, program)
    }
}
