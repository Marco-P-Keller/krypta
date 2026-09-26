#if DEBUG
import Foundation
import KryptaCore
import KryptaMessenger

/// Nur in Debug-Builds: die App gegen einen Server im Speicher, mit einem
/// zweiten, echten Messenger im selben Prozess als Gesprächspartnerin.
///
/// Start mit dem Argument `-KryptaDemo`. Nichts davon berührt Firebase,
/// den Schlüsselbund oder die Platte.
@MainActor
enum DemoMode {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-KryptaDemo") }

    /// Die echte App, aber gegen einen Server im Speicher (UI-Tests).
    static var isOffline: Bool { ProcessInfo.processInfo.arguments.contains("-KryptaOffline") }

    /// `-KryptaSeedFlutter <pfad>`: vor dem Start einen Flutter-Speicher
    /// anlegen (flutter_store.json aus test/interop) und alles Native
    /// löschen — so, als käme das Update gerade aus dem App Store.
    static func seedFlutterStoreIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        // `-KryptaReset`: frisch wie nach der Installation (UI-Tests).
        if args.contains("-KryptaReset") {
            try? FileVault().wipe()
            Keychain.wipe()
            NotificationIndexStore.delete()
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        guard let i = args.firstIndex(of: "-KryptaSeedFlutter"), i + 1 < args.count,
              let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var secrets = json["secrets"] as? [String: String],
              let files = json["files"] as? [String: String] else { return }
        try? FileVault().wipe()
        Keychain.wipe()
        // Die Codes im Testspeicher sind Attrappen; ohne sie öffnet die App direkt.
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        for key in ["krypta_code_secret", "krypta_code_delete", "krypta_vault_hash", "krypta_vault_enabled", "krypta_cfg_biometric", "krypta_cfg_language"] {
            secrets.removeValue(forKey: key)
        }
        secrets["krypta_cfg_calculator_lock"] = "false"
        FlutterMigration.seedForTesting(secrets: secrets, files: files.compactMapValues { Data(base64Encoded: $0) })
    }

    /// Hält die Gegenseite am Leben.
    private static var peers: [MessengerEngine] = []

    static func makeEngine() async -> MessengerEngine {
        let relay = MemoryRelay()
        let config = EngineConfig(ackJitter: 0...0, announceTimeout: 1, tick: 1)
        let me = MessengerEngine(userId: "demoUserMe00000000001", identity: .generate(), relay: relay, vault: MemoryVault(), config: config)
        let lena = MessengerEngine(userId: "demoLena000000000002", identity: .generate(), relay: relay, vault: MemoryVault(), config: config)
        let jonas = MessengerEngine(userId: "demoJonas00000000003", identity: .generate(), relay: relay, vault: MemoryVault(), config: config)
        peers = [lena, jonas]
        await me.start()
        await lena.start()
        await jonas.start()

        // Lena ist per QR verbunden (sofort fest und verifiziert).
        _ = await me.addContact(qr: lena.myQRPayload)
        await wait { lena.contact(me.userId)?.requestState == .established }
        guard let myChat = me.chat(forContact: lena.userId), let lenaChat = lena.chat(forContact: me.userId) else { return me }
        me.rename(chatId: myChat.id, to: "Lena")

        await lena.send(chatId: lenaChat.id, text: "Hey! Hast du die neue Version schon ausprobiert?")
        await wait { me.messages(in: myChat.id).count == 1 }
        await me.send(chatId: myChat.id, text: "Gerade eben. Sieht jetzt aus wie eine echte iPhone-App 😄")
        await me.send(chatId: myChat.id, text: "Und rechnet immer noch als Tarnung.")
        await lena.send(chatId: lenaChat.id, text: "Perfekt. Die Adresse schicke ich dir mit Löschfrist:", options: .plain)
        await lena.send(chatId: lenaChat.id, text: "Lindenstraße 12, 3. Stock", options: SendOptions(selfDestruct: 3600))
        await lena.send(chatId: lenaChat.id, text: "Der Code für die Tür", options: SendOptions(password: "blau"))
        await lena.send(chatId: lenaChat.id, text: "Nur einmal lesen 🤫", options: SendOptions(oneTime: true))
        await wait { me.messages(in: myChat.id).count >= 7 }

        // Jonas hat angefragt, aber noch keine Antwort.
        _ = await jonas.addContact(id: me.userId)
        await wait { !me.incomingRequests.isEmpty }
        return me
    }

    private static func wait(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}
#endif
