import Foundation

/// BIP39: Zufall ↔ Wörter ↔ Seed.
///
/// Krypta erzeugt 12 Wörter (128 Bit Zufall, so stark wie secp256k1 selbst)
/// und liest beim Wiederherstellen 12 bis 24. Gespeichert wird nur der
/// Zufall; Wörter und Seed entstehen bei Bedarf und werden danach verworfen.
public enum Mnemonic {
    public static let validWordCounts: Set<Int> = [12, 15, 18, 21, 24]

    public enum Failure: Error, Equatable, Sendable {
        case wordCount
        /// Position (ab 0) des ersten Worts, das nicht in der Liste steht.
        case unknownWord(Int)
        case checksum
    }

    /// Neuer Zufall für eine Wallet: 16 Bytes.
    public static func generateEntropy() -> SecretBytes {
        SecretBytes(SecureRandom.bytes(16))
    }

    /// Zufall → Wörter.
    public static func words(entropy: [UInt8]) throws -> [String] {
        guard [16, 20, 24, 28, 32].contains(entropy.count) else { throw BitcoinError.invalidSeed }
        let checksumBits = entropy.count / 4
        let checksum = Hashes.sha256(entropy)[0]
        var bits = [Bool]()
        bits.reserveCapacity(entropy.count * 8 + checksumBits)
        for byte in entropy {
            for i in (0..<8).reversed() { bits.append(byte >> UInt8(i) & 1 == 1) }
        }
        for i in 0..<checksumBits { bits.append(checksum >> UInt8(7 - i) & 1 == 1) }
        var words = [String]()
        for chunk in stride(from: 0, to: bits.count, by: 11) {
            var index = 0
            for bit in bits[chunk..<(chunk + 11)] { index = index << 1 | (bit ? 1 : 0) }
            words.append(wordlist[index])
        }
        return words
    }

    /// Wörter → Zufall, mit Prüfsumme. Groß/klein und Leerraum egal.
    public static func entropy(words input: [String]) throws -> SecretBytes {
        let words = input.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        guard validWordCounts.contains(words.count) else { throw Failure.wordCount }
        var bits = [Bool]()
        bits.reserveCapacity(words.count * 11)
        for (position, word) in words.enumerated() {
            guard let index = index[word] else { throw Failure.unknownWord(position) }
            for i in (0..<11).reversed() { bits.append(index >> i & 1 == 1) }
        }
        let checksumBits = words.count * 11 / 33
        let entropyBits = bits.count - checksumBits
        var entropy = [UInt8](repeating: 0, count: entropyBits / 8)
        for i in 0..<entropyBits where bits[i] {
            entropy[i / 8] |= 1 << UInt8(7 - i % 8)
        }
        let hash = Hashes.sha256(entropy)[0]
        for i in 0..<checksumBits where bits[entropyBits + i] != (hash >> UInt8(7 - i) & 1 == 1) {
            entropy.wipe()
            throw Failure.checksum
        }
        let secret = SecretBytes(entropy)
        entropy.wipe()
        return secret
    }

    /// Wörter → 64-Byte-Seed (PBKDF2-HMAC-SHA512, 2048 Runden). Ohne
    /// Passphrase, wie in der App.
    public static func seed(words: [String], passphrase: String = "") -> SecretBytes {
        let sentence = words.joined(separator: " ").decomposedStringWithCompatibilityMapping
        var password = Array(sentence.utf8)
        defer { password.wipe() }
        let salt = Array(("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping.utf8)
        return SecretBytes(Hashes.pbkdf2SHA512(password: password, salt: salt, iterations: 2048, keyLength: 64))
    }

    /// Zufall → Seed, ohne die Wörter aufzuheben.
    public static func seed(entropy: [UInt8]) throws -> SecretBytes {
        seed(words: try words(entropy: entropy))
    }

    public static func isWord(_ word: String) -> Bool { index[word.lowercased()] != nil }

    /// Vorschläge beim Eintippen. Die ersten vier Buchstaben bestimmen jedes
    /// Wort eindeutig.
    public static func suggestions(for prefix: String, limit: Int = 4) -> [String] {
        let p = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !p.isEmpty else { return [] }
        return Array(wordlist.lazy.filter { $0.hasPrefix(p) }.prefix(limit))
    }

    static let index: [String: Int] = Dictionary(uniqueKeysWithValues: wordlist.enumerated().map { ($1, $0) })
}
