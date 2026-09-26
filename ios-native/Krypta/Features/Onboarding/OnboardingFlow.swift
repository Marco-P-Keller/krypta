import SwiftUI

/// Einrichtung: Willkommen → Tarnung → Geheimcode → Löschcode → Face ID.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var app

    enum Step: Hashable { case disguise, secretCode, deleteCode, biometrics }

    @State private var path: [Step] = []
    @State private var secret = ""
    @State private var deleteCode = ""
    @State private var useCalculator = true
    @State private var isWorking = false
    @State private var failed = false

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.disguise) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .disguise:
                        DisguiseView { use in
                            useCalculator = use
                            path.append(use ? .secretCode : .biometrics)
                        }
                    case .secretCode:
                        PasscodeEntryView(
                            title: "Geheimcode festlegen",
                            message: "Gib diesen Code im Rechner ein und tippe auf =, um Krypta zu öffnen.",
                            symbol: "lock.fill", tint: .accentColor
                        ) { code in
                            secret = code
                            path.append(.deleteCode)
                            return nil
                        }
                    case .deleteCode:
                        PasscodeEntryView(
                            title: "Löschcode festlegen",
                            message: "Im Notfall: dieser Code + = löscht sofort alles — ohne Rückfrage.",
                            symbol: "trash.fill", tint: .red
                        ) { code in
                            guard code != secret else { return String(localized: "Der Löschcode muss sich vom Geheimcode unterscheiden.") }
                            deleteCode = code
                            path.append(.biometrics)
                            return nil
                        }
                    case .biometrics:
                        BiometricsOfferView(isWorking: isWorking) { biometric in
                            finish(biometric: biometric)
                        }
                    }
                }
        }
        .alert("Einrichtung fehlgeschlagen", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Prüfe die Internetverbindung und versuche es noch einmal.")
        }
    }

    private func finish(biometric: Bool) {
        isWorking = true
        Task {
            do {
                let codes = useCalculator ? (secret: secret, delete: deleteCode) : nil
                try await app.completeOnboarding(.init(codes: codes, biometric: biometric))
            } catch {
                failed = true
            }
            isWorking = false
        }
    }
}

// MARK: - Willkommen

private struct WelcomeView: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 36) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.top, 56)

                    Text("Willkommen bei Krypta")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 28) {
                        Feature(symbol: "lock.fill", title: "Ende-zu-Ende-verschlüsselt",
                                text: "Nachrichten sind nur auf deinem Gerät und dem deines Kontakts lesbar. Nicht einmal der Server sieht, wer schreibt.")
                        Feature(symbol: "person.crop.circle.badge.questionmark", title: "Ohne Telefonnummer",
                                text: "Kein Konto, keine E-Mail. Kontakte fügst du per QR-Code oder Kennung hinzu.")
                        Feature(symbol: "timer", title: "Nachrichten, die verschwinden",
                                text: "Mit Löschfristen, „nach dem Ansehen“ oder nur einmal zu öffnen.")
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 32)
            }
            Button(action: next) {
                Text("Fortfahren").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .accessibilityIdentifier("onboarding.continue")
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct Feature: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Tarnung

private struct DisguiseView: View {
    let choose: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.top, 32)
                    Text("Als Rechner tarnen?")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Krypta öffnet sich dann als gewöhnlicher Rechner. Erst dein Geheimcode, gefolgt von =, zeigt deine Chats. Ein zweiter Code löscht im Notfall alles.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
            VStack(spacing: 12) {
                Button { choose(true) } label: {
                    Text("Tarnung einrichten").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding.disguise.yes")
                Button("Ohne Tarnung fortfahren") { choose(false) }
                    .accessibilityIdentifier("onboarding.disguise.no")
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Face ID

private struct BiometricsOfferView: View {
    let isWorking: Bool
    let finish: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: Biometrics.available == .none ? "checkmark.seal.fill" : Biometrics.symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text(Biometrics.available == .none ? "Fast fertig" : "\(Biometrics.name) verwenden?")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(Biometrics.available == .none
                     ? "Krypta erzeugt jetzt deine Schlüssel. Sie verlassen dieses Gerät nie."
                     : "Zusätzlich zum Code fragt Krypta nach \(Biometrics.name), bevor sich deine Chats öffnen.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                if isWorking {
                    ProgressView("Schlüssel werden erzeugt …")
                        .frame(height: 50)
                } else if Biometrics.available == .none {
                    Button { finish(false) } label: { Text("Fertig").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        Task {
                            if await Biometrics.authenticate(reason: "\(Biometrics.name) für Krypta aktivieren") { finish(true) }
                        }
                    } label: { Text("\(Biometrics.name) aktivieren").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    Button("Nicht jetzt") { finish(false) }
                        .accessibilityIdentifier("onboarding.biometrics.skip")
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .navigationBarBackButtonHidden(isWorking)
    }
}
