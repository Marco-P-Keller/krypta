import Foundation
import KryptaCore
import Security

/// Der Index für die Mitteilungen im Schlüsselbund, den App und
/// Notification Service Extension teilen.
///
/// Darin stehen je Kontakt der Schlüssel für den Anhänger und der Name —
/// nie ein Nachrichteninhalt und nie ein Schlüssel, mit dem sich eine
/// Nachricht entschlüsseln ließe. Lesbar erst nach dem ersten Entsperren
/// des iPhones und nie in Backups ("ThisDeviceOnly").
enum NotificationIndexStore {
    /// Team-Präfix aus project.yml (DEVELOPMENT_TEAM) und die geteilte Gruppe
    /// aus den Entitlements beider Targets.
    static let accessGroup = "B97SQSQBMR.com.calcchat.ww.shared"
    private static let service = "com.calcchat.ww.shared"
    private static let account = "notify.index"

    static func load() -> NotificationIndex? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(NotificationIndex.self, from: data)
    }

    static func save(_ index: NotificationIndex) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }

    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }
}
