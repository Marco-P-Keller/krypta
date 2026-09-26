import Foundation
import KryptaCore

/// Geheim- und Löschcode des Rechners.
///
/// Gespeichert wird nur Argon2id(Code) mit eigenem Salz, im selben Format
/// wie die Flutter-Fassung: "base64(salz):base64(hash)".
enum AccessCodes {
    static let minimumLength = 4

    enum Match { case none, secret, delete }

    static func set(secret: String, delete: String) throws {
        Keychain.set(try hash(secret), for: .secretCode)
        Keychain.set(try hash(delete), for: .deleteCode)
    }

    static func clear() {
        Keychain.delete(.secretCode)
        Keychain.delete(.deleteCode)
    }

    static var isConfigured: Bool { Keychain.string(.secretCode) != nil }

    /// Prüft eine Eingabe gegen beide Codes. Der Löschcode hat Vorrang.
    /// Argon2id braucht einen Moment — deshalb nicht auf dem Main Thread.
    static func check(_ input: String) async -> Match {
        let digits = input.filter(\.isNumber)
        guard digits.count >= minimumLength else { return .none }
        let secret = Keychain.string(.secretCode)
        let delete = Keychain.string(.deleteCode)
        return await Task.detached(priority: .userInitiated) {
            if let delete, verify(digits, against: delete) { return Match.delete }
            if let secret, verify(digits, against: secret) { return Match.secret }
            return Match.none
        }.value
    }

    static func hash(_ code: String) throws -> String {
        let salt = Data.random(count: 16)
        let hash = try Primitives.argon2id(password: Data(code.utf8), salt: salt)
        return "\(salt.base64):\(hash.base64)"
    }

    static func verify(_ candidate: String, against stored: String) -> Bool {
        let parts = stored.split(separator: ":").map(String.init)
        guard parts.count == 2, let salt = Data(base64: parts[0]), let expected = Data(base64: parts[1]),
              let hash = try? Primitives.argon2id(password: Data(candidate.utf8), salt: salt) else { return false }
        return hash.constantTimeEquals(expected)
    }
}
