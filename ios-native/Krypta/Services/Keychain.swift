import Foundation
import Security

/// Schlüsselbund für alles Geheime: Identität, Tresorschlüssel, Codes.
///
/// Nie in Backups oder auf andere Geräte übertragen ("ThisDeviceOnly").
/// Die zwei Schlüssel, mit denen sich Inhalte entschlüsseln lassen —
/// Identität und Tresorschlüssel —, sind nur lesbar, solange das iPhone
/// entsperrt ist. Forensik-Werkzeuge, die ein gesperrtes, aber seit dem
/// Einschalten schon einmal entsperrtes Gerät auslesen ("AFU"), kommen so
/// nicht an die Chats. Der Rest (Kennung, Schalter, Code-Hashes) bleibt wie in
/// der Flutter-Fassung nach dem ersten Entsperren lesbar.
enum Keychain {
    private static let service = "com.calcchat.ww.native"

    enum Key: String, CaseIterable {
        case identityPrivate = "identity.private"
        case identityPublic = "identity.public"
        case userId = "user.id"
        case vaultKey = "vault.key"
        case secretCode = "code.secret"
        case deleteCode = "code.delete"
        case calculatorLock = "lock.calculator"
        case biometricLock = "lock.biometric"
        case failedUnlocks = "lock.failures"
        case vaultPassword = "vault.password"
        case vaultFailures = "vault.failures"
        case vaultLastFail = "vault.lastfail"

        var accessibility: CFString {
            switch self {
            case .identityPrivate, .vaultKey: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            default: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    static func data(_ key: Key) -> Data? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func set(_ data: Data, for key: Key) {
        let query = base(key)
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: key.accessibility]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = key.accessibility
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Einträge aus älteren Fassungen auf die strengere Klasse heben.
    /// Nur bei entsperrtem Gerät aufrufen (die App ist dann vorne).
    static func tightenProtection() {
        for key in Key.allCases where key.accessibility == kSecAttrAccessibleWhenUnlockedThisDeviceOnly {
            SecItemUpdate(base(key) as CFDictionary, [kSecAttrAccessible as String: key.accessibility] as CFDictionary)
        }
    }

    static func string(_ key: Key) -> String? { data(key).map { String(decoding: $0, as: UTF8.self) } }
    static func set(_ string: String, for key: Key) { set(Data(string.utf8), for: key) }
    static func bool(_ key: Key) -> Bool { string(key) == "1" }
    static func set(_ flag: Bool, for key: Key) { set(flag ? "1" : "0", for: key) }

    static func delete(_ key: Key) {
        SecItemDelete(base(key) as CFDictionary)
    }

    /// Alles, was Krypta je in den Schlüsselbund gelegt hat.
    static func wipe() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    private static func base(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
