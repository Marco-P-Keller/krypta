import FirebaseAuth
import Foundation
import KryptaCore
import KryptaMessenger
import Observation
import SwiftUI

/// Wo die App gerade steht, und die Wege dazwischen.
///
/// Zugang wie ZugangsPolicy der Flutter-Fassung: mit Rechner-Tarnung
/// öffnet der Rechner, sonst mit Face ID der Sperrbildschirm, sonst direkt.
/// Ist ein Tresor-Passwort gesetzt, kommt es nach Rechner und Face ID als
/// letzte Tür.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case onboarding
        case calculator
        case locked
        case vaultPassword
        case unlocking
        case unlocked
        /// Notfall-Löschung läuft: nichts mehr zu sehen.
        case wiping
    }

    private(set) var phase: Phase = .launching
    private(set) var engine: MessengerEngine?
    /// Verdeckt den Inhalt, sobald die App nicht vorne ist (App-Umschalter).
    var privacyCover = false
    /// Der Bildschirm wird aufgezeichnet oder gespiegelt.
    var isCaptured = UIScreen.main.isCaptured

    /// Chats aus Bildschirmfotos und Aufnahmen heraushalten. Vorgabe: an.
    var screenshotShield: Bool = !UserDefaults.standard.bool(forKey: "shield.off") {
        didSet { UserDefaults.standard.set(!screenshotShield, forKey: "shield.off") }
    }

    /// Aus einer angetippten Mitteilung: dieses Ziel öffnen, sobald die
    /// Chats zu sehen sind (also erst nach Rechner, Face ID und Passwort).
    var pendingOpen: PushService.Target?

    init() {
        PushService.shared.open = { [weak self] target in self?.pendingOpen = target }
        PushService.shared.shouldPresent = { [weak self] target in self?.shouldPresentBanner(for: target) ?? false }
        PushService.shared.deliverPendingTarget()
    }

    /// Banner in der App nur bei offenen Chats, und nicht für den Chat,
    /// der gerade vorne ist.
    private func shouldPresentBanner(for target: PushService.Target?) -> Bool {
        guard phase == .unlocked, !privacyCover, let target, let engine else { return false }
        switch target {
        case .chat(let contactId):
            guard let active = engine.activeChatId else { return true }
            return engine.chat(active)?.recipientId != contactId
        case .requests:
            return true
        }
    }

    var calculatorLock: Bool { Keychain.bool(.calculatorLock) }
    var biometricLock: Bool { Keychain.bool(.biometricLock) }

    /// Wohin gesperrt wird — `nil` heißt: keine Sperre eingerichtet.
    var lockTarget: Phase? {
        #if DEBUG
        if DemoMode.isActive { return nil }
        #endif
        if calculatorLock { return .calculator }
        if biometricLock { return .locked }
        if VaultPassword.isSet { return .vaultPassword }
        return nil
    }

    // MARK: - Start

    func launch() {
        guard phase == .launching else { return }
        // Identität und Tresorschlüssel sind nur bei entsperrtem iPhone
        // lesbar. Startet iOS die App bei gesperrtem Gerät, sähe es sonst aus,
        // als gäbe es kein Konto — und die App böte die Einrichtung an.
        // Warten, bis entsperrt ist (RootView ruft dann erneut).
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        // Eine Notfall-Löschung wurde unterbrochen (App beendet): zu Ende bringen.
        if EmergencyWipe.isPending {
            phase = .wiping
            Task { await finishWipe(engine: nil, uid: EmergencyWipe.pendingUserId) }
            return
        }
        #if DEBUG
        if DemoMode.isActive {
            Task {
                engine = await DemoMode.makeEngine()
                phase = .unlocked
            }
            return
        }
        #endif
        #if DEBUG
        DemoMode.seedFlutterStoreIfRequested()
        #endif
        // Erster Start nach dem Update von der Flutter-App: deren Daten
        // übernehmen, bevor irgendetwas anderes passiert.
        if FlutterMigration.isPending {
            FlutterMigration.run()
        }
        guard Keychain.string(.userId) != nil, identity() != nil else {
            phase = .onboarding
            return
        }
        if let target = lockTarget {
            phase = target
        } else {
            Task { await unlock() }
        }
    }

    private func identity() -> KeyPair? {
        guard let priv = Keychain.data(.identityPrivate), let pub = Keychain.data(.identityPublic),
              let pair = try? KeyPair.from(privateKey: priv), pair.publicKey == pub else { return nil }
        return pair
    }

    // MARK: - Einrichtung

    struct SetupChoice {
        var codes: (secret: String, delete: String)?
        var biometric: Bool
    }

    /// Anonym anmelden, Identität erzeugen, Zugang festlegen.
    func completeOnboarding(_ choice: SetupChoice) async throws {
        let uid: String
        #if DEBUG
        if DemoMode.isOffline {
            uid = "offline" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(21)
        } else {
            uid = try await Auth.auth().signInAnonymously().user.uid
        }
        #else
        uid = try await Auth.auth().signInAnonymously().user.uid
        #endif
        let pair = KeyPair.generate()
        Keychain.set(pair.privateKey, for: .identityPrivate)
        Keychain.set(pair.publicKey, for: .identityPublic)
        Keychain.set(uid, for: .userId)
        if let codes = choice.codes {
            try AccessCodes.set(secret: codes.secret, delete: codes.delete)
            Keychain.set(true, for: .calculatorLock)
        } else {
            AccessCodes.clear()
            Keychain.set(false, for: .calculatorLock)
        }
        Keychain.set(choice.biometric, for: .biometricLock)
        await unlock()
    }

    // MARK: - Entsperren und Sperren

    func unlock() async {
        phase = .unlocking
        guard let uid = await currentUserId(), let identity = identity() else {
            phase = .onboarding
            return
        }
        guard phase == .unlocking else { return }
        Keychain.tightenProtection()
        if engine == nil || engine?.userId != uid {
            guard let vault = try? FileVault() else { return }
            var relay: Relay = FirebaseRelay()
            #if DEBUG
            if DemoMode.isOffline { relay = MemoryRelay() }
            #endif
            engine = MessengerEngine(userId: uid, identity: identity, relay: relay, vault: vault)
        }
        await engine?.start()
        // Während des Startens verlassen oder gelöscht: nicht doch noch öffnen.
        guard phase == .unlocking else { return }
        withAnimation(.smooth) { phase = .unlocked }
        #if DEBUG
        if DemoMode.isOffline, let engine { PushService.shared.attach(engine) }
        if DemoMode.isActive || DemoMode.isOffline { return }
        #endif
        if let engine { await PushService.shared.start(userId: uid, engine: engine) }
    }

    /// Firebase merkt sich die anonyme Anmeldung selbst. Ist sie weg (neu
    /// installiert, Schlüsselbund aber erhalten), gibt es eine neue Kennung.
    private func currentUserId() async -> String? {
        #if DEBUG
        if DemoMode.isOffline { return Keychain.string(.userId) }
        #endif
        if let user = Auth.auth().currentUser { return user.uid }
        guard let user = try? await Auth.auth().signInAnonymously().user else { return Keychain.string(.userId) }
        Keychain.set(user.uid, for: .userId)
        return user.uid
    }

    /// Mit Face ID vom Sperrbildschirm.
    func unlockWithBiometrics() async {
        guard await Biometrics.authenticate(reason: String(localized: "Krypta entsperren")) else { return }
        await passedGate()
    }

    /// Nach dem Rechner: Face ID folgt, wenn eingerichtet.
    func secretCodeEntered() async {
        if biometricLock {
            guard await Biometrics.authenticate(reason: String(localized: "Krypta entsperren")) else { return }
        }
        await passedGate()
    }

    /// Rechner und Face ID sind durch — fehlt noch das Tresor-Passwort?
    private func passedGate() async {
        if VaultPassword.isSet {
            withAnimation(.smooth) { phase = .vaultPassword }
        } else {
            await unlock()
        }
    }

    /// Die letzte Tür. Beim fünften Fehlversuch wird alles gelöscht.
    func submitVaultPassword(_ password: String) async -> VaultPassword.Attempt {
        let result = await VaultPassword.attempt(password)
        switch result {
        case .unlocked: await unlock()
        case .wipe: await emergencyWipe()
        case .wrong, .lockedOut: break
        }
        return result
    }

    /// „Zurück" vom Tresor-Passwort: wieder vor die erste Tür.
    func cancelVaultPassword() {
        guard phase == .vaultPassword, let target = lockTarget, target != .vaultPassword else { return }
        withAnimation(.smooth) { phase = target }
    }

    func lock() {
        guard let target = lockTarget, phase == .unlocked || phase == .unlocking || phase == .vaultPassword else { return }
        engine?.stop()
        phase = target
    }

    /// Wer die App verlässt, landet beim Zurückkommen wieder vor der Tür —
    /// egal wie kurz: App-Umschalter, Kontrollzentrum, Mitteilungszentrale,
    /// Home. Schon `.inactive` sperrt; nur Fragen, die Krypta selbst stellt
    /// (Face ID, Kamera, Mitteilungen), zählen nicht als Verlassen.
    func scenePhaseChanged(_ scene: ScenePhase) {
        privacyCover = scene != .active
        switch scene {
        case .inactive:
            if !SystemPrompt.isShowing { lock() }
        case .background:
            Task { await engine?.setForeground(false) }
            lock()
        case .active:
            Task { await engine?.setForeground(true) }
            if phase == .unlocked { PushService.shared.clearDelivered() }
        default:
            break
        }
    }

    // MARK: - Einstellungen

    func setCalculator(secret: String, delete: String) throws {
        try AccessCodes.set(secret: secret, delete: delete)
        Keychain.set(true, for: .calculatorLock)
    }

    func disableCalculator() {
        AccessCodes.clear()
        Keychain.set(false, for: .calculatorLock)
    }

    func setBiometric(_ on: Bool) async -> Bool {
        if on, !(await Biometrics.authenticate(reason: String(localized: "\(Biometrics.name) für Krypta aktivieren"))) { return false }
        Keychain.set(on, for: .biometricLock)
        return true
    }

    // MARK: - Notfall

    /// Alles weg: Gerät, Schlüsselbund, Server. Danach Neubeginn.
    ///
    /// Sofort: Der Bildschirm ist im selben Augenblick leer, und das Gerät
    /// wird zuerst geräumt — ohne Tresorschlüssel sind die Dateien
    /// Datenmüll, auch wenn die App gleich darauf beendet wird. Der Server
    /// folgt; bricht das ab, macht der nächste Start weiter.
    func emergencyWipe() async {
        guard phase != .wiping else { return }
        let engine = self.engine
        let uid = engine?.userId ?? Keychain.string(.userId)
        phase = .wiping
        EmergencyWipe.markPending(userId: uid)
        engine?.stop()
        Keychain.wipe()
        FileVault.destroy()
        PushService.shared.clearDelivered()
        await finishWipe(engine: engine, uid: uid)
    }

    private func finishWipe(engine: MessengerEngine?, uid: String?) async {
        // Ohne Netz wartet Firestore endlos; länger als das hält niemand den
        // leeren Bildschirm aus. Was offen bleibt, räumt der Server: nicht
        // abgeholte Nachrichten nach 24 Stunden.
        await EmergencyWipe.withDeadline(seconds: 15) {
            if let engine {
                await engine.wipeEverything()
            } else if let uid {
                #if DEBUG
                if !DemoMode.isOffline { try? await FirebaseRelay().deleteAllUserData(uid: uid) }
                #else
                try? await FirebaseRelay().deleteAllUserData(uid: uid)
                #endif
            }
        }
        // Auch wenn der Server nicht erreichbar war: das alte Konto ist auf
        // diesem Gerät vergessen, die nächste Einrichtung bekommt ein neues.
        try? Auth.auth().signOut()
        Keychain.wipe()
        FileVault.destroy()
        await PushService.shared.wipe()
        EmergencyWipe.clear()
        self.engine = nil
        withAnimation(.smooth) { phase = .onboarding }
    }
}
