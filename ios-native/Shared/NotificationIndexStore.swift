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
        write(data, account: account)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
        resetBadge()
    }

    // MARK: - Zahl am App-Symbol

    /// Die Extension zählt mit, die App setzt beim Öffnen auf null.
    /// Nur eine Zahl — kein Absender, kein Inhalt.
    static func nextBadge() -> Int {
        let next = badge + 1
        write(Data(String(next).utf8), account: badgeAccount)
        return next
    }

    static func resetBadge() {
        SecItemDelete(query(account: badgeAccount) as CFDictionary)
    }

    private static let badgeAccount = "notify.badge"

    private static var badge: Int {
        var q = query(account: badgeAccount)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return 0 }
        return Int(String(decoding: data, as: UTF8.self)) ?? 0
    }

    private static func write(_ data: Data, account: String) {
        let q = query(account: account)
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static var base: [String: Any] { query(account: account) }

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }
}
