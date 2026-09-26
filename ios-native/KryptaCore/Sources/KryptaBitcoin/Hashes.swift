import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Nur für Tests unter Linux: swift-crypto hat dieselbe Schnittstelle.
import Crypto
#endif

/// Die Hashes, die Bitcoin braucht. SHA-2 und HMAC kommen aus CryptoKit;
/// RIPEMD-160 hat CryptoKit nicht, es steht unten (es hasht nur öffentliche
/// Schlüssel, nie etwas Geheimes).
public enum Hashes {
    public static func sha256(_ data: [UInt8]) -> [UInt8] { Array(SHA256.hash(data: data)) }

    /// SHA-256 zweimal: Transaktionskennungen, Blockköpfe, Prüfsummen.
    public static func hash256(_ data: [UInt8]) -> [UInt8] { sha256(sha256(data)) }

    /// RIPEMD-160(SHA-256(x)): aus einem öffentlichen Schlüssel wird die Adresse.
    public static func hash160(_ data: [UInt8]) -> [UInt8] { RIPEMD160.hash(sha256(data)) }

    public static func hmacSHA512(key: [UInt8], data: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    /// PBKDF2 mit HMAC-SHA512 (RFC 8018), für BIP39. Selbst geschrieben, damit
    /// es auf allen Plattformen derselbe Code ist; geprüft mit den Vektoren
    /// von BIP39 (Trezor).
    public static func pbkdf2SHA512(password: [UInt8], salt: [UInt8], iterations: Int, keyLength: Int) -> [UInt8] {
        precondition(iterations > 0 && keyLength > 0)
        let key = SymmetricKey(data: password)
        var derived = [UInt8]()
        var block: UInt32 = 1
        while derived.count < keyLength {
            var input = salt
            input.appendBE(block)
            var u = Array(HMAC<SHA512>.authenticationCode(for: input, using: key))
            var t = u
            for _ in 1..<iterations {
                u = Array(HMAC<SHA512>.authenticationCode(for: u, using: key))
                for i in 0..<t.count { t[i] ^= u[i] }
            }
            derived.append(contentsOf: t)
            u.wipe()
            t.wipe()
            block += 1
        }
        return Array(derived.prefix(keyLength))
    }
}

/// RIPEMD-160 nach Dobbertin, Bosselaers und Preneel (1996).
enum RIPEMD160 {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: (UInt32, UInt32, UInt32, UInt32, UInt32) = (0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0)

        var padded = message
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        padded.appendLE(UInt64(message.count) &* 8)

        var x = [UInt32](repeating: 0, count: 16)
        for chunk in stride(from: 0, to: padded.count, by: 64) {
            for i in 0..<16 {
                let o = chunk + 4 * i
                x[i] = UInt32(padded[o]) | UInt32(padded[o + 1]) << 8 | UInt32(padded[o + 2]) << 16 | UInt32(padded[o + 3]) << 24
            }
            var (al, bl, cl, dl, el) = h
            var (ar, br, cr, dr, er) = h
            for j in 0..<80 {
                let round = j / 16
                var t = al &+ f(round, bl, cl, dl) &+ x[rl[j]] &+ kl[round]
                t = rotl(t, sl[j]) &+ el
                al = el; el = dl; dl = rotl(cl, 10); cl = bl; bl = t

                t = ar &+ f(4 - round, br, cr, dr) &+ x[rr[j]] &+ kr[round]
                t = rotl(t, sr[j]) &+ er
                ar = er; er = dr; dr = rotl(cr, 10); cr = br; br = t
            }
            let t = h.1 &+ cl &+ dr
            h.1 = h.2 &+ dl &+ er
            h.2 = h.3 &+ el &+ ar
            h.3 = h.4 &+ al &+ br
            h.4 = h.0 &+ bl &+ cr
            h.0 = t
        }
        var out = [UInt8]()
        for word in [h.0, h.1, h.2, h.3, h.4] { out.appendLE(word) }
        return out
    }

    private static func rotl(_ x: UInt32, _ n: Int) -> UInt32 { (x << UInt32(n)) | (x >> UInt32(32 - n)) }

    private static func f(_ round: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch round {
        case 0: x ^ y ^ z
        case 1: (x & y) | (~x & z)
        case 2: (x | ~y) ^ z
        case 3: (x & z) | (y & ~z)
        default: x ^ (y | ~z)
        }
    }

    private static let kl: [UInt32] = [0x0000_0000, 0x5A82_7999, 0x6ED9_EBA1, 0x8F1B_BCDC, 0xA953_FD4E]
    private static let kr: [UInt32] = [0x50A2_8BE6, 0x5C4D_D124, 0x6D70_3EF3, 0x7A6D_76E9, 0x0000_0000]

    private static let rl: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13,
    ]
    private static let rr: [Int] = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11,
    ]
    private static let sl: [Int] = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6,
    ]
    private static let sr: [Int] = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11,
    ]
}
