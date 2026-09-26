import Foundation
import KryptaCore

/// Das Tresor-Passwort: eine zweite Sperre nach Rechner-Code oder Face ID.
///
/// Wie in der Flutter-Fassung (SecureStorageService, VaultPasswordScreen):
/// gespeichert wird nur Argon2id mit eigenem Salz, der Zähler für
/// Fehlversuche übersteht jeden Neustart, nach jedem Fehler wächst die
/// Pause (2, 4, 8, 16 s), und beim fünften Fehler wird alles gelöscht.
enum VaultPassword {
    static let maxAttempts = 5
    /// Ab hier warnt die Sperre, dass gelöscht wird.
    static let warnAfter = 2
    static let minimumLength = 6

    enum Attempt: Equatable {
        case unlocked
        case wrong(remaining: Int)
        case lockedOut(seconds: Int)
        case wipe
    }

    static var isSet: Bool { Keychain.string(.vaultPassword) != nil }

    static func set(_ password: String) async throws {
        let stored = try await Task.detached(priority: .userInitiated) { try AccessCodes.hash(password) }.value
        Keychain.set(stored, for: .vaultPassword)
        resetFailures()
    }

    static func remove() {
        Keychain.delete(.vaultPassword)
        resetFailures()
    }

    static var failures: Int { Int(Keychain.string(.vaultFailures) ?? "") ?? 0 }

    /// 2^Fehlversuche Sekunden, höchstens zwei Minuten.
    static func delay(after failures: Int) -> TimeInterval {
        failures <= 0 ? 0 : min(120, pow(2, Double(failures)))
    }

    static func lockoutRemaining(now: Date = Date()) -> TimeInterval {
        guard failures > 0, let ms = Double(Keychain.string(.vaultLastFail) ?? "") else { return 0 }
        let until = Date(timeIntervalSince1970: ms / 1000).addingTimeInterval(delay(after: failures))
        return max(0, until.timeIntervalSince(now))
    }

    /// Prüft das Passwort. Der Zähler steigt *bevor* gerechnet wird — wer die
    /// App mitten in der Prüfung abschießt, bekommt keinen Gratisversuch.
    static func attempt(_ password: String) async -> Attempt {
        if failures >= maxAttempts { return .wipe }
        let wait = lockoutRemaining()
        if wait > 0 { return .lockedOut(seconds: Int(wait.rounded(.up))) }
        guard let stored = Keychain.string(.vaultPassword) else { return .unlocked }

        let before = failures
        recordFailure(count: before + 1)
        let ok = await Task.detached(priority: .userInitiated) { AccessCodes.verify(password, against: stored) }.value
        if ok {
            resetFailures()
            return .unlocked
        }
        if before + 1 >= maxAttempts { return .wipe }
        return .wrong(remaining: maxAttempts - before - 1)
    }

    private static func recordFailure(count: Int) {
        Keychain.set(String(count), for: .vaultFailures)
        Keychain.set(String(Int(Date().timeIntervalSince1970 * 1000)), for: .vaultLastFail)
    }

    static func resetFailures() {
        Keychain.delete(.vaultFailures)
        Keychain.delete(.vaultLastFail)
    }
}
