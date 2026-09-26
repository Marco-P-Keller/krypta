import Foundation
import KryptaCore
import KryptaMessenger

/// Der lokale Speicher: ein Blob je Slot, XChaCha20-Poly1305 mit dem Slot
/// als AAD, der Schlüssel im Schlüsselbund.
///
/// Dateinamen sind Hashes der Slots, damit auf der Platte nicht einmal
/// steht, wie viele Chats es gibt und wie sie heißen.
///
/// Datenschutzklasse "complete unless open": Ist das iPhone gesperrt, lässt
/// sich keine Datei mehr öffnen — neue schreiben geht aber, damit ein
/// Speichervorgang kurz nach dem Sperren nicht verloren geht (der Schlüssel
/// liegt dann noch im Arbeitsspeicher).
final class FileVault: Vault, @unchecked Sendable {
    private let directory: URL
    private let key: Data
    private let lock = NSLock()

    init() throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = base.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUnlessOpen,
        ])
        Self.tightenProtection(directory)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)

        if let existing = Keychain.data(.vaultKey), existing.count == 32 {
            key = existing
        } else {
            key = Data.random(count: 32)
            Keychain.set(key, for: .vaultKey)
        }
    }

    private func url(_ slot: String) -> URL {
        let name = Primitives.sha256(Data("krypta-vault|\(slot)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    func load(_ slot: String) throws -> Data? {
        try lock.withLock {
            guard let blob = try? Data(contentsOf: url(slot)) else { return nil }
            return try Envelope.openLocal(blob, key: key, slot: slot)
        }
    }

    func save(_ data: Data, slot: String) throws {
        try lock.withLock {
            let blob = try Envelope.sealLocal(data, key: key, slot: slot)
            try blob.write(to: url(slot), options: [.atomic, .completeFileProtectionUnlessOpen])
        }
    }

    func delete(_ slot: String) throws {
        _ = lock.withLock { try? FileManager.default.removeItem(at: url(slot)) }
    }

    /// Ordner und Dateien älterer Fassungen auf die strengere Klasse heben.
    private static func tightenProtection(_ directory: URL) {
        let fm = FileManager.default
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: directory.path)
        for file in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: file.path)
        }
    }

    /// Notfall: Schlüssel und Dateien weg, ohne den Tresor erst zu öffnen.
    static func destroy() {
        Keychain.delete(.vaultKey)
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        try? FileManager.default.removeItem(at: base.appendingPathComponent("Vault", isDirectory: true))
    }

    func wipe() throws {
        lock.withLock {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
