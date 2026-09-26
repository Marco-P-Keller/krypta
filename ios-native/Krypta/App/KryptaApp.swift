import FirebaseCore
import SwiftUI

@main
struct KryptaApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { model.launch() }
                .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
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
            case .unlocked:
                if let engine = model.engine {
                    ChatsView()
                        .environment(engine)
                        .transition(.opacity)
                }
            }

            if model.privacyCover && model.phase != .calculator {
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
