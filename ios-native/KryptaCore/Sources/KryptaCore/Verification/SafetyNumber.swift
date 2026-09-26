import Foundation

/// 60-stellige Sicherheitsnummer, symmetrisch für beide Seiten —
/// wie security/verification/safety_number.dart.
public enum SafetyNumber {
    public static let currentVersion = 1

    public static func generate(localUserId: String, localIdentity: Data, remoteUserId: String, remoteIdentity: Data, version: Int = currentVersion) -> String {
        // Dart vergleicht Strings nach UTF-16-Codeeinheiten; für die
        // ASCII-Kennungen von Firebase ist das dieselbe Ordnung wie hier.
        let pairs = localUserId.utf16.lexicographicallyPrecedes(remoteUserId.utf16) || localUserId == remoteUserId
            ? [(localUserId, localIdentity), (remoteUserId, remoteIdentity)]
            : [(remoteUserId, remoteIdentity), (localUserId, localIdentity)]
        return digits(fingerprint(pairs[0].0, pairs[0].1, version), 30)
            + digits(fingerprint(pairs[1].0, pairs[1].1, version), 30)
    }

    /// Gruppen zu fünf Ziffern.
    public static func formatted(_ number: String) -> String {
        stride(from: 0, to: number.count, by: 5).map { i -> String in
            let start = number.index(number.startIndex, offsetBy: i)
            let end = number.index(start, offsetBy: min(5, number.count - i))
            return String(number[start..<end])
        }.joined(separator: " ")
    }

    static func fingerprint(_ userId: String, _ publicKey: Data, _ version: Int) -> Data {
        var data = Data([0x00, UInt8(version)]) + userId.utf8Data + publicKey
        for _ in 0..<5200 {
            var next = Primitives.sha512(data)
            swap(&data, &next)
            next.zero()
        }
        return data
    }

    static func digits(_ hash: Data, _ count: Int) -> String {
        var out = ""
        var i = 0
        let bytes = [UInt8](hash)
        while out.count < count, i * 2 + 1 < bytes.count {
            let value = (Int(bytes[i * 2]) << 8 | Int(bytes[i * 2 + 1])) % 100_000
            out += String(format: "%05d", value)
            i += 1
        }
        return String(out.prefix(count)).padding(toLength: count, withPad: "0", startingAt: 0)
    }
}
