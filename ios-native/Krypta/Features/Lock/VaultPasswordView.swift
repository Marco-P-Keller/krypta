import SwiftUI

/// Die letzte Tür vor den Chats: das Tresor-Passwort.
///
/// Fünf Versuche insgesamt, über Neustarts hinweg. Nach jedem Fehler wächst
/// die Pause; ab dem dritten Fehler steht da, wie viele noch bleiben, bevor
/// alles gelöscht wird.
struct VaultPasswordView: View {
    @Environment(AppModel.self) private var app
    @State private var password = ""
    @State private var message: String?
    @State private var warning = false
    @State private var checking = false
    @State private var lockedUntil: Date?
    @State private var shake = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 6) {
                Text("Tresor-Passwort")
                    .font(.title2.weight(.bold))
                Text("Gib dein Passwort ein, um deine Chats zu öffnen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            SecureField("Passwort", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focused)
                .onSubmit(submit)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 24)
                .modifier(Shake(animatableData: CGFloat(shake)))
                .disabled(checking || lockedUntil != nil)
                .accessibilityIdentifier("vault.password")

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let until = lockedUntil, until > context.date {
                    Text("Nächster Versuch in \(Int(until.timeIntervalSince(context.date).rounded(.up))) s")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let message {
                    Label(message, systemImage: warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(warning ? .red : .secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .frame(minHeight: 36)

            Spacer()
            VStack(spacing: 12) {
                Button(action: submit) {
                    Group {
                        if checking { ProgressView() } else { Text("Entsperren") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || checking || lockedUntil != nil)
                .accessibilityIdentifier("vault.unlock")
                if app.lockTarget != .vaultPassword {
                    Button("Zurück") { app.cancelVaultPassword() }
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            focused = true
            startLockout(VaultPassword.lockoutRemaining())
            if VaultPassword.failures >= VaultPassword.warnAfter {
                warn(remaining: VaultPassword.maxAttempts - VaultPassword.failures)
            }
        }
    }

    private func submit() {
        guard !password.isEmpty, !checking, lockedUntil == nil else { return }
        let input = password
        checking = true
        Task {
            let result = await app.submitVaultPassword(input)
            checking = false
            password = ""
            switch result {
            case .unlocked, .wipe:
                break
            case .wrong(let remaining):
                withAnimation(.default) { shake += 1 }
                if VaultPassword.failures >= VaultPassword.warnAfter {
                    warn(remaining: remaining)
                } else {
                    message = String(localized: "Falsches Passwort.")
                    warning = false
                }
                startLockout(VaultPassword.lockoutRemaining())
            case .lockedOut(let seconds):
                startLockout(TimeInterval(seconds))
            }
        }
    }

    private func warn(remaining: Int) {
        message = String(localized: "Falsches Passwort. Nach \(remaining) weiteren Fehlversuchen wird alles gelöscht.")
        warning = true
    }

    private func startLockout(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let until = Date().addingTimeInterval(seconds)
        lockedUntil = until
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if lockedUntil == until {
                lockedUntil = nil
                focused = true
            }
        }
    }
}
