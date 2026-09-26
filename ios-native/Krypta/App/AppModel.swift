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
        if engine == nil || engine?.userId != uid {
            guard let vault = try? FileVault() else { return }
            var relay: Relay = FirebaseRelay()
            #if DEBUG
            if DemoMode.isOffline { relay = MemoryRelay() }
            #endif
            engine = MessengerEngine(userId: uid, identity: identity, relay: relay, vault: vault)
        }
        await engine?.start()
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

    func scenePhaseChanged(_ scene: ScenePhase) {
        privacyCover = scene != .active
        switch scene {
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

    /// Alles weg: Server, Gerät, Schlüsselbund. Danach Neubeginn.
    func emergencyWipe() async {
        if let engine {
            await engine.wipeEverything()
        } else if let uid = Keychain.string(.userId) {
            try? await FirebaseRelay().deleteAllUserData(uid: uid)
        }
        try? FileVault().wipe()
        await PushService.shared.wipe()
        Keychain.wipe()
        engine = nil
        withAnimation(.smooth) { phase = .onboarding }
    }
}
