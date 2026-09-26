import Foundation
import Security

/// Schlüsselbund für alles Geheime: Identität, Tresorschlüssel, Codes.
///
/// Wie in der Flutter-Fassung erst nach dem ersten Entsperren lesbar und nie
/// in Backups oder auf andere Geräte übertragen ("ThisDeviceOnly").
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
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
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
