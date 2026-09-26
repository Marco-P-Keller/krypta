import FirebaseCore
import FirebaseFirestore
import SwiftUI

@main
struct KryptaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        Self.keepFirestoreInMemory()
        FirebaseRelay.configureSealedApp()
        PushService.shared.configure()
        _model = State(initialValue: AppModel())
    }

    /// Firestore legt sonst jede empfangene Nachricht (verschlüsselt) in
    /// einen Zwischenspeicher auf dem Gerät. Den braucht Krypta nicht — die
    /// Chats liegen im eigenen Tresor —, also nur im Arbeitsspeicher, und
    /// was ältere Fassungen dort hinterlassen haben, kommt weg.
    private static func keepFirestoreInMemory() {
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: support.appendingPathComponent("firestore", isDirectory: true))
        }
        let settings = Firestore.firestore().settings
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .background { EmergencyOverlayInstaller(model: model) }
                .onAppear { model.launch() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                    model.launch()
                }
                .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
                .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                    model.isCaptured = UIScreen.main.isCaptured
                }
        }
    }
}

/// Zeigt, was zur Phase gehört — und verdeckt alles, wenn die App nicht vorne ist.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .launching, .unlocking, .wiping:
                Color(.systemBackground).ignoresSafeArea()
            case .onboarding:
                OnboardingFlow()
                    .transition(.opacity)
            case .calculator:
                CalculatorView()
                    .transition(.opacity)
            case .locked:
                LockView()
                    .transition(.opacity)
            case .vaultPassword:
                VaultPasswordView()
                    .transition(.opacity)
            case .unlocked:
                if let engine = model.engine {
                    // Über die Grenze des Schutzbehälters reicht SwiftUI die
                    // Umgebung nicht weiter — deshalb hier ausdrücklich.
                    ScreenshotShield(isEnabled: model.screenshotShield) {
                        ChatsView()
                            .environment(engine)
                            .environment(model)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }

            if model.privacyCover && model.phase != .calculator {
                PrivacyCover()
                    .transition(.opacity)
            }

            // Aufnahme oder Spiegelung läuft und die geschützte Fläche fehlt
            // auf diesem System: dann eben alles abdecken.
            if model.isCaptured && model.screenshotShield && !ScreenshotProtection.isEffective && model.phase == .unlocked {
                PrivacyCover()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.phase)
        // Durch die Tür (Rechner-Code, Face ID, Passwort): ein kurzes „Klick".
        // Ohne eingerichtete Sperre öffnet die App still.
        .sensoryFeedback(trigger: model.phase) { _, new in
            new == .unlocked && model.lockTarget != nil ? .success : nil
        }
        .animation(.easeOut(duration: 0.15), value: model.privacyCover)
    }
}

/// Im App-Umschalter sieht man nur eine unscharfe Fläche.
struct PrivacyCover: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThickMaterial)
            .ignoresSafeArea()
            .overlay {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }
}
