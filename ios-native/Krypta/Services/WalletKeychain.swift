import Foundation
import KryptaBitcoin
import KryptaWallet
import LocalAuthentication
import Security

/// Der Schlüssel der Bitcoin-Wallet im Schlüsselbund.
///
/// - Der Zufall, aus dem die zwölf Wörter entstehen, liegt nur auf diesem
///   Gerät (`ThisDeviceOnly`, nie in Backups oder iCloud) und ist an Face ID
///   oder den Gerätecode gebunden (`userPresence`): Selbst Krypta kommt ohne
///   diese Bestätigung nicht an ihn heran. Gelesen wird er nur zum Senden
///   und zum Anzeigen der Wörter, und nur für diesen Moment.
/// - Die öffentlichen Kontoschlüssel (daraus entstehen die Adressen) liegen
///   ohne Rückfrage lesbar daneben, nur bei entsperrtem iPhone.
///
/// Hat das iPhone keinen Code, lässt iOS keine Bindung an ihn zu; dann liegt
/// der Zufall ohne sie im Schlüsselbund, und die Wallet sagt das deutlich.
///
/// Derselbe Dienst wie `Keychain`: `Keychain.wipe()` (Löschcode, Notfall,
/// „Alles löschen") nimmt die Wallet mit.
final class WalletKeychain: WalletSecrets, @unchecked Sendable {
    static let shared = WalletKeychain()

    private let service = "com.calcchat.ww.native"
    private let seedAccount = "wallet.seed"
    private let publicAccount = "wallet.public"
    private let lock = NSLock()

    /// Hat das iPhone einen Code? Ohne ihn gibt es keine Bindung an Face ID/Code.
    static var deviceHasPasscode: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var hasWallet: Bool { publicKeys != nil && seedExists }

    /// Ist der Zufall an Face ID oder Code gebunden?
    var isProtectedByDeviceAuth: Bool {
        var query = base(seedAccount)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        // Würde iOS schon für die Attribute fragen, ist der Eintrag gebunden.
        if status == errSecInteractionNotAllowed { return true }
        guard status == errSecSuccess, let attributes = result as? [String: Any] else { return false }
        return attributes[kSecAttrAccessControl as String] != nil
    }

    private var seedExists: Bool {
        var query = base(seedAccount)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private var publicKeys: WalletPublicKeys? {
        var query = base(publicAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WalletPublicKeys.self, from: data)
    }

    func accountKey(for network: BitcoinNetwork) -> ExtendedPublicKey? {
        publicKeys?.key(for: network)
    }

    func create() throws {
        try lock.withLock {
            guard !hasWallet else { return }
            let entropy = Mnemonic.generateEntropy()
            try store(entropy, WalletPublicKeys(entropy: entropy.copy))
        }
    }

    func restore(words: [String]) throws {
        let entropy = try Mnemonic.entropy(words: words)
        let keys = try WalletPublicKeys(entropy: entropy.copy)
        try lock.withLock { try store(entropy, keys) }
    }

    /// Fragt nach Face ID oder Code und gibt den Zufall zurück.
    @MainActor
    func entropy(reason: String) async throws -> SecretBytes {
        let context = LAContext()
        if Self.deviceHasPasscode {
            let ok = await SystemPrompt.during {
                (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
            }
            guard ok else { throw WalletFailure.authenticationCancelled }
        }
        var query = base(seedAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        // Mit dem eben bestätigten Kontext fragt iOS nicht noch einmal.
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, [16, 20, 24, 28, 32].contains(data.count) else {
            throw status == errSecUserCanceled || status == errSecAuthFailed ? WalletFailure.authenticationCancelled : WalletFailure.noWallet
        }
        return SecretBytes(data)
    }

    // MARK: - Schreiben

    private func store(_ entropy: SecretBytes, _ keys: WalletPublicKeys) throws {
        SecItemDelete(base(seedAccount) as CFDictionary)
        SecItemDelete(base(publicAccount) as CFDictionary)

        var seed = base(seedAccount)
        seed[kSecValueData as String] = Data(entropy.copy)
        var error: Unmanaged<CFError>?
        if Self.deviceHasPasscode,
           let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) {
            seed[kSecAttrAccessControl as String] = access
        } else {
            seed[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        var status = SecItemAdd(seed as CFDictionary, nil)
        if status != errSecSuccess, seed[kSecAttrAccessControl as String] != nil {
            // Ohne Bindung, aber nie ohne Wallet.
            seed.removeValue(forKey: kSecAttrAccessControl as String)
            seed[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(seed as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WalletFailure.noWallet }

        var pub = base(publicAccount)
        pub[kSecValueData as String] = try JSONEncoder().encode(keys)
        pub[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(pub as CFDictionary, nil) == errSecSuccess else {
            SecItemDelete(base(seedAccount) as CFDictionary)
            throw WalletFailure.noWallet
        }
    }

    private func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
