import FirebaseCore
import SwiftUI

@main
struct KryptaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        PushService.shared.configure()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { model.launch() }
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
            case .launching, .unlocking:
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
