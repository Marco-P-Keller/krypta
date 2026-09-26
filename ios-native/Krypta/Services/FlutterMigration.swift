import Foundation
import KryptaCore
import KryptaMessenger
import Security

/// Erster Start nach dem Update von der Flutter-App.
///
/// Dieselbe Bundle-ID heißt: derselbe Container, derselbe Schlüsselbund,
/// dieselbe Secure Enclave. Übernommen werden Identität, Kennung, Codes,
/// Tresor-Passwort samt Fehlversuchen, Einstellungen, Kontakte, Chats,
/// Nachrichten, Sitzungen und das Schlüsselprotokoll. Die Anmeldung bei
/// Firebase liegt im Schlüsselbund des Firebase-SDK und gilt ohnehin weiter.
///
/// Danach ist die Tür dieselbe wie vorher: gleicher Geheimcode, gleicher
/// Löschcode, gleiches Tresor-Passwort. Erst wenn alles in der neuen Form
/// steht, verschwinden die alten Daten — Schlüsselbundeinträge, Dateien und
/// der Schlüssel in der Secure Enclave.
enum FlutterMigration {
    private static let service = "flutter_secure_storage_service"
    private static let enclaveTag = Data("com.krypta.hw.wrapping".utf8)

    private static var storeDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("krypta_store", isDirectory: true)
    }

    /// Noch nicht eingerichtet, aber Flutter hat eine Identität hinterlassen.
    static var isPending: Bool {
        Keychain.string(.userId) == nil && readSecret("krypta_id_priv") != nil
    }

    static func run() {
        let secrets = readAllSecrets()
        // Ohne Datenordner ist das kein Update, sondern ein Rest im
        // Schlüsselbund nach dem Löschen der App (der überlebt das). Die
        // Flutter-App hat solche Reste beim Neustart weggeräumt — hier auch.
        guard let dir = storeDirectory, FileManager.default.fileExists(atPath: dir.path) else {
            removeFlutterData()
            return
        }

        var store: FlutterImport.Store = [:]
        if let key = databaseKey(secrets) {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "enc" {
                let slot = file.deletingPathExtension().lastPathComponent
                guard let blob = try? Data(contentsOf: file),
                      let plain = FlutterImport.openStoreBlob(blob, key: key, slot: slot) else { continue }
                store[slot] = String(decoding: plain, as: UTF8.self)
            }
        }

        guard let result = try? FlutterImport.convert(secrets: secrets, store: store),
              let vault = try? FileVault() else { return }
        FlutterImport.write(result, to: vault)

        let s = result.settings
        if let secret = s.secretCodeHash { Keychain.set(secret, for: .secretCode) }
        if let delete = s.deleteCodeHash { Keychain.set(delete, for: .deleteCode) }
        Keychain.set(s.calculatorLock, for: .calculatorLock)
        Keychain.set(s.biometricLock, for: .biometricLock)
        if let vaultHash = s.vaultPasswordHash {
            Keychain.set(vaultHash, for: .vaultPassword)
            if s.vaultFailures > 0 {
                Keychain.set(String(s.vaultFailures), for: .vaultFailures)
                if let ms = s.vaultLastFailMs { Keychain.set(String(ms), for: .vaultLastFail) }
            }
        }
        PushService.isEnabled = s.pushEnabled
        if let lang = s.languageCode, !lang.isEmpty {
            // Die Sprachwahl der Flutter-App gilt weiter — wie die Auswahl in
            // den iOS-Einstellungen, ab dem nächsten Start.
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        }
        // Identität und Kennung zuletzt: erst sie machen die Einrichtung
        // vollständig. Bricht vorher etwas ab, läuft die Übernahme erneut.
        Keychain.set(result.identity.privateKey, for: .identityPrivate)
        Keychain.set(result.identity.publicKey, for: .identityPublic)
        Keychain.set(result.userId, for: .userId)

        removeFlutterData()
    }

    // MARK: - Datenbankschlüssel

    /// Im Klartext im Schlüsselbund oder — auf Geräten mit Secure Enclave —
    /// dort mit ECIES verpackt (AppDelegate.swift der Flutter-App).
    private static func databaseKey(_ secrets: [String: String]) -> Data? {
        if let plain = secrets["krypta_db_key"].flatMap(Data.init(base64:)), plain.count == 32 { return plain }
        guard let wrapped = secrets["krypta_db_key_hw"].flatMap(Data.init(base64:)), let key = enclaveKey() else { return nil }
        var error: Unmanaged<CFError>?
        let data = SecKeyCreateDecryptedData(key, .eciesEncryptionCofactorVariableIVX963SHA256AESGCM, wrapped as CFData, &error) as Data?
        error?.release()
        return data
    }

    private static func enclaveKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: enclaveTag,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item,
              CFGetTypeID(item) == SecKeyGetTypeID() else { return nil }
        return (item as! SecKey)
    }

    // MARK: - flutter_secure_storage

    private static func readSecret(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readAllSecrets() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8) else { continue }
            out[account] = value
        }
        return out
    }

    private static func removeFlutterData() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: enclaveTag] as CFDictionary)
        if let dir = storeDirectory { try? FileManager.default.removeItem(at: dir) }
    }

    #if DEBUG
    /// Nur für den UI-Test: legt einen Flutter-Speicher an, wie ihn
    /// test/interop/flutter_store_fixture_test.dart erzeugt.
    static func seedForTesting(secrets: [String: String], files: [String: Data]) {
        removeFlutterData()
        for (key, value) in secrets {
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: Data(value.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            SecItemAdd(add as CFDictionary, nil)
        }
        guard let dir = storeDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in files { try? data.write(to: dir.appendingPathComponent(name)) }
    }
    #endif
}
