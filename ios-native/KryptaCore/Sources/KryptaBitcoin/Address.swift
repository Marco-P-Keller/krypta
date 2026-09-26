import Foundation

/// Eine Empfängeradresse, geprüft und in ihr Ausgabeskript übersetzt.
///
/// Angenommen werden nur Arten, die heute jede Wallet ausgeben kann (P2PKH,
/// P2SH, Segwit v0, Taproot). Künftige Segwit-Versionen lehnt Krypta ab,
/// statt Geld an ein Skript zu schicken, das noch niemand ausgeben kann.
public struct BitcoinAddress: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        case p2pkh, p2sh, p2wpkh, p2wsh, p2tr
    }

    /// Kanonische Schreibweise (Segwit klein).
    public let string: String
    public let kind: Kind
    public let scriptPubKey: [UInt8]
    public let network: BitcoinNetwork

    public var description: String { string }

    public init(_ text: String, network: BitcoinNetwork) throws {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.count <= 100, raw.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw BitcoinError.invalidAddress
        }
        self.network = network
        if raw.lowercased().hasPrefix(network.hrp + "1") {
            guard let (version, program) = SegwitAddress.decode(hrp: network.hrp, raw) else { throw BitcoinError.invalidAddress }
            switch (version, program.count) {
            case (0, 20): kind = .p2wpkh
            case (0, 32): kind = .p2wsh
            case (1, 32): kind = .p2tr
            default: throw BitcoinError.unsupportedAddress
            }
            scriptPubKey = [version == 0 ? 0x00 : UInt8(0x50 + version), UInt8(program.count)] + program
            string = raw.lowercased()
            return
        }
        if let payload = Base58.decodeCheck(raw), payload.count == 21 {
            let hash = Array(payload.dropFirst())
            switch payload[0] {
            case network.p2pkhVersion:
                kind = .p2pkh
                scriptPubKey = [0x76, 0xA9, 0x14] + hash + [0x88, 0xAC]
            case network.p2shVersion:
                kind = .p2sh
                scriptPubKey = [0xA9, 0x14] + hash + [0x87]
            default:
                throw Self.isOtherNetwork(raw, network) ? BitcoinError.wrongNetwork : BitcoinError.invalidAddress
            }
            string = raw
            return
        }
        throw Self.isOtherNetwork(raw, network) ? BitcoinError.wrongNetwork : BitcoinError.invalidAddress
    }

    /// Die Adresse zu einem eigenen Schlüssel (BIP84, P2WPKH).
    public static func p2wpkh(publicKey: [UInt8], network: BitcoinNetwork) -> BitcoinAddress {
        precondition(publicKey.count == 33)
        let program = Hashes.hash160(publicKey)
        let text = SegwitAddress.encode(hrp: network.hrp, version: 0, program: program)!
        return BitcoinAddress(string: text, kind: .p2wpkh, scriptPubKey: [0x00, 0x14] + program, network: network)
    }

    init(string: String, kind: Kind, scriptPubKey: [UInt8], network: BitcoinNetwork) {
        self.string = string
        self.kind = kind
        self.scriptPubKey = scriptPubKey
        self.network = network
    }

    /// Die Adresse zu einem Ausgabeskript, soweit es eine Standardform hat.
    public static func from(scriptPubKey s: [UInt8], network: BitcoinNetwork) -> BitcoinAddress? {
        let isV0 = s.count >= 2 && s[0] == 0x00 && ((s.count == 22 && s[1] == 0x14) || (s.count == 34 && s[1] == 0x20))
        if isV0 {
            guard let text = SegwitAddress.encode(hrp: network.hrp, version: 0, program: Array(s.dropFirst(2))) else { return nil }
            return BitcoinAddress(string: text, kind: s.count == 22 ? .p2wpkh : .p2wsh, scriptPubKey: s, network: network)
        }
        if s.count == 34, s[0] == 0x51, s[1] == 0x20 {
            guard let text = SegwitAddress.encode(hrp: network.hrp, version: 1, program: Array(s.dropFirst(2))) else { return nil }
            return BitcoinAddress(string: text, kind: .p2tr, scriptPubKey: s, network: network)
        }
        if s.count == 25, s[0] == 0x76, s[1] == 0xA9, s[2] == 0x14, s[23] == 0x88, s[24] == 0xAC {
            return BitcoinAddress(string: Base58.encodeCheck([network.p2pkhVersion] + s[3..<23]), kind: .p2pkh, scriptPubKey: s, network: network)
        }
        if s.count == 23, s[0] == 0xA9, s[1] == 0x14, s[22] == 0x87 {
            return BitcoinAddress(string: Base58.encodeCheck([network.p2shVersion] + s[2..<22]), kind: .p2sh, scriptPubKey: s, network: network)
        }
        return nil
    }

    /// Ab diesem Betrag gilt eine Ausgabe nicht mehr als Staub (Bitcoin Core,
    /// 3 sat/vB): kleiner wird sie nicht weitergeleitet.
    public var dustLimit: Int64 { Self.dustLimit(scriptPubKey: scriptPubKey) }

    public static func dustLimit(scriptPubKey s: [UInt8]) -> Int64 {
        let outputSize = 8 + [UInt8].varIntSize(s.count) + s.count
        let isWitness = s.count >= 4 && s.count <= 42 && (s[0] == 0x00 || (0x51...0x60).contains(s[0])) && Int(s[1]) == s.count - 2
        let spendSize = isWitness ? 32 + 4 + 1 + 107 / 4 + 4 : 32 + 4 + 1 + 107 + 4
        return Int64(outputSize + spendSize) * 3
    }

    /// Eine gültige Adresse, nur für ein anderes Netz? Dann sagt die Meldung
    /// das, statt nur „ungültig".
    private static func isOtherNetwork(_ raw: String, _ network: BitcoinNetwork) -> Bool {
        if let (hrp, _, _) = Bech32.decode(raw) {
            return hrp != network.hrp && BitcoinNetwork.allCases.contains { $0.hrp == hrp }
        }
        if let payload = Base58.decodeCheck(raw), payload.count == 21 {
            let versions: Set<UInt8> = network == .mainnet ? [0x6F, 0xC4] : [0x00, 0x05]
            return versions.contains(payload[0])
        }
        return false
    }
}

/// `bitcoin:`-Links (BIP21), wie sie in QR-Codes stehen.
public struct PaymentRequest: Equatable, Sendable {
    public let address: BitcoinAddress
    public let amount: Int64?
    public let label: String?
    public let message: String?

    public init(address: BitcoinAddress, amount: Int64? = nil, label: String? = nil, message: String? = nil) {
        self.address = address
        self.amount = amount
        self.label = label
        self.message = message
    }

    /// Nimmt einen Link oder eine blanke Adresse.
    public static func parse(_ text: String, network: BitcoinNetwork) throws -> PaymentRequest {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count <= 2048 else { throw BitcoinError.invalidAddress }
        guard raw.lowercased().hasPrefix("bitcoin:") else {
            return PaymentRequest(address: try BitcoinAddress(raw, network: network))
        }
        let rest = raw.dropFirst("bitcoin:".count)
        let parts = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let address = try BitcoinAddress(String(parts[0]), network: network)
        var amount: Int64?, label: String?, message: String?
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0]).lowercased()
                let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? "") : ""
                switch key {
                case "amount":
                    guard let sats = BitcoinAmount.parse(value, allowComma: false), sats > 0 else { throw BitcoinError.invalidAddress }
                    amount = sats
                case "label": label = value
                case "message": message = value
                default:
                    // BIP21: Unbekanntes mit req- heißt „ohne mich geht es nicht".
                    if key.hasPrefix("req-") { throw BitcoinError.unsupportedAddress }
                }
            }
        }
        return PaymentRequest(address: address, amount: amount, label: label, message: message)
    }

    public var uri: String {
        var s = "bitcoin:" + address.string
        if let amount { s += "?amount=" + BitcoinAmount.plainBTC(amount) }
        return s
    }
}

/// Beträge in Satoshi, ohne Gleitkomma.
public enum BitcoinAmount {
    public static let satsPerBTC: Int64 = 100_000_000
    public static let maxSats: Int64 = 21_000_000 * satsPerBTC

    /// „0.001", „0,001", „.5", „12" → Satoshi. Höchstens acht Nachkommastellen,
    /// kein Vorzeichen, keine Tausendertrennung, nicht über 21 Mio. BTC.
    public static func parse(_ text: String, allowComma: Bool = true) -> Int64? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if allowComma { s = s.replacingOccurrences(of: ",", with: ".") }
        guard !s.isEmpty, s.count <= 20, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard !(parts[0].isEmpty && fraction.isEmpty), fraction.count <= 8, whole.count <= 8,
              let w = Int64(whole), let f = Int64(fraction.padding(toLength: 8, withPad: "0", startingAt: 0)) else { return nil }
        let sats = w * satsPerBTC + f
        guard sats <= maxSats else { return nil }
        return sats
    }

    /// Satoshi als ganze Zahl („12500").
    public static func parseSats(_ text: String) -> Int64? {
        let s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "'", with: "")
        guard !s.isEmpty, s.count <= 16, s.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int64(s), v <= maxSats else { return nil }
        return v
    }

    /// Für Links und das Protokoll: Punkt, ohne überflüssige Nullen („0.001").
    public static func plainBTC(_ sats: Int64) -> String {
        let sign = sats < 0 ? "-" : ""
        let v = sats.magnitude
        let whole = v / UInt64(satsPerBTC), fraction = v % UInt64(satsPerBTC)
        var frac = String(fraction)
        frac = String(repeating: "0", count: 8 - frac.count) + frac
        while frac.hasSuffix("0") { frac.removeLast() }
        return sign + String(whole) + (frac.isEmpty ? "" : "." + frac)
    }

    /// Für die Anzeige: immer acht Stellen, in Dreiergruppen wie viele
    /// Wallets („0.001 234 00").
    public static func formatBTC(_ sats: Int64, decimalSeparator: String = ".") -> String {
        let sign = sats < 0 ? "-" : ""
        let v = sats.magnitude
        let whole = v / UInt64(satsPerBTC), fraction = v % UInt64(satsPerBTC)
        var frac = String(fraction)
        frac = String(repeating: "0", count: 8 - frac.count) + frac
        let chars = Array(frac)
        let grouped = String(chars[0..<2]) + "\u{2009}" + String(chars[2..<5]) + "\u{2009}" + String(chars[5..<8])
        return sign + String(whole) + decimalSeparator + grouped
    }
}
