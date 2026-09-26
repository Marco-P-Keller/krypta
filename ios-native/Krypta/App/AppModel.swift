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
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case onboarding
        case calculator
        case locked
        case unlocking
        case unlocked
    }

    private(set) var phase: Phase = .launching
    private(set) var engine: MessengerEngine?
    /// Verdeckt den Inhalt, sobald die App nicht vorne ist (App-Umschalter).
    var privacyCover = false

    var calculatorLock: Bool { Keychain.bool(.calculatorLock) }
    var biometricLock: Bool { Keychain.bool(.biometricLock) }

    /// Wohin gesperrt wird — `nil` heißt: keine Sperre eingerichtet.
    var lockTarget: Phase? {
        #if DEBUG
        if DemoMode.isActive { return nil }
        #endif
        if calculatorLock { return .calculator }
        if biometricLock { return .locked }
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
        let user = try await Auth.auth().signInAnonymously().user
        let pair = KeyPair.generate()
        Keychain.set(pair.privateKey, for: .identityPrivate)
        Keychain.set(pair.publicKey, for: .identityPublic)
        Keychain.set(user.uid, for: .userId)
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
            engine = MessengerEngine(userId: uid, identity: identity, relay: FirebaseRelay(), vault: vault)
        }
        await engine?.start()
        withAnimation(.smooth) { phase = .unlocked }
    }

    /// Firebase merkt sich die anonyme Anmeldung selbst. Ist sie weg (neu
    /// installiert, Schlüsselbund aber erhalten), gibt es eine neue Kennung.
    private func currentUserId() async -> String? {
        if let user = Auth.auth().currentUser { return user.uid }
        guard let user = try? await Auth.auth().signInAnonymously().user else { return Keychain.string(.userId) }
        Keychain.set(user.uid, for: .userId)
        return user.uid
    }

    /// Mit Face ID vom Sperrbildschirm.
    func unlockWithBiometrics() async {
        guard await Biometrics.authenticate(reason: "Krypta entsperren") else { return }
        await unlock()
    }

    /// Nach dem Rechner: Face ID folgt, wenn eingerichtet.
    func secretCodeEntered() async {
        if biometricLock {
            guard await Biometrics.authenticate(reason: "Krypta entsperren") else { return }
        }
        await unlock()
    }

    func lock() {
        guard let target = lockTarget, phase == .unlocked || phase == .unlocking else { return }
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
        if on, !(await Biometrics.authenticate(reason: "\(Biometrics.name) für Krypta aktivieren")) { return false }
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
        Keychain.wipe()
        engine = nil
        withAnimation(.smooth) { phase = .onboarding }
    }
}
