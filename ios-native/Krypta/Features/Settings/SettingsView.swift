import KryptaMessenger
import SwiftUI
import UserNotifications

/// Einstellungen — aufgebaut wie die Einstellungen von iOS.
struct SettingsView: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showMyCode = false
    @State private var setupCalculator = false
    @State private var confirmDisableCalculator = false
    @State private var confirmWipe = false
    @State private var biometric = Keychain.bool(.biometricLock)
    @State private var calculator = Keychain.bool(.calculatorLock)
    @State private var push = PushService.isEnabled
    @State private var pushNames = PushService.showsNames
    @State private var pushDenied = false
    @State private var vaultPassword = VaultPassword.isSet

    var body: some View {
        @Bindable var engine = engine
        NavigationStack {
            Form {
                Section {
                    Button { showMyCode = true } label: {
                        HStack(spacing: 14) {
                            Avatar(id: engine.userId, name: "User \(engine.userId)", size: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Meine Kennung").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                Text(engine.userId).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "qrcode").font(.title2).foregroundStyle(.tint)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Toggle(isOn: Binding(get: { push }, set: { on in
                        push = on
                        Task {
                            await PushService.shared.setEnabled(on, engine: engine)
                            await refreshPushPermission()
                        }
                    })) {
                        Label("Mitteilungen", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("settings.push")
                    if push {
                        Toggle(isOn: Binding(get: { pushNames }, set: { on in
                            pushNames = on
                            PushService.showsNames = on
                            PushService.shared.updateIndex(engine)
                        })) {
                            Label("Absender nennen", systemImage: "person.text.rectangle")
                        }
                    }
                    if push && pushDenied {
                        Button {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        } label: {
                            Label("In den iOS-Einstellungen erlauben", systemImage: "gear")
                        }
                    }
                } header: {
                    Text("Mitteilungen")
                } footer: {
                    Text(push && pushNames
                         ? "Auf dem Sperrbildschirm steht „Neue Nachricht von …“ mit dem Namen, den du dem Kontakt gegeben hast. Was in der Nachricht steht, erfahren weder die Mitteilung noch Apple oder Google."
                         : "Auf dem Sperrbildschirm steht nur „Neue Nachricht“ — ohne Absender und ohne Inhalt.")
                }

                Section {
                    Toggle(isOn: $engine.readReceiptsEnabled) {
                        Label("Lesebestätigungen", systemImage: "checkmark.message")
                    }
                    Toggle(isOn: $engine.chatPreviewEnabled) {
                        Label("Vorschau in der Chatliste", systemImage: "text.bubble")
                    }
                    Toggle(isOn: Binding(get: { app.screenshotShield }, set: { app.screenshotShield = $0 })) {
                        Label("Bildschirmfotos verhindern", systemImage: "eye.slash")
                    }
                    .accessibilityIdentifier("settings.shield")
                } header: {
                    Text("Datenschutz")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zustellungen werden immer gemeldet, weil an ihnen der Start der Löschfristen hängt. Lesebestätigungen nur, wenn du sie einschaltest.")
                        if app.screenshotShield {
                            Text(ScreenshotProtection.isEffective
                                 ? "Bildschirmfotos und Aufnahmen zeigen statt deiner Chats eine leere Fläche. Dein Kontakt erfährt trotzdem davon."
                                 : "Auf diesem iPhone lässt sich der Schutz nicht einrichten. Bei Aufnahmen verdeckt Krypta den Bildschirm; von Bildschirmfotos erfährt dein Kontakt.")
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(get: { calculator }, set: { on in
                        if on { setupCalculator = true } else { confirmDisableCalculator = true }
                    })) {
                        Label("Als Rechner tarnen", systemImage: "plus.forwardslash.minus")
                    }
                    NavigationLink {
                        VaultPasswordSettings(isSet: $vaultPassword)
                    } label: {
                        LabeledContent {
                            Text(vaultPassword ? "An" : "Aus")
                        } label: {
                            Label("Tresor-Passwort", systemImage: "lock.rectangle.stack")
                        }
                    }
                    .accessibilityIdentifier("settings.vault")
                    if Biometrics.available != .none {
                        Toggle(isOn: Binding(get: { biometric }, set: { on in
                            Task { if await app.setBiometric(on) { biometric = on } }
                        })) {
                            Label(Biometrics.name, systemImage: Biometrics.symbol)
                        }
                    }
                } header: {
                    Text("Sperre")
                } footer: {
                    Text(calculator
                         ? "Krypta öffnet sich als Rechner. Geheimcode + = zeigt deine Chats, Löschcode + = löscht alles."
                         : (biometric ? "Ohne Tarnung öffnet sich Krypta nach \(Biometrics.name)." : "Ohne Tarnung öffnet sich Krypta direkt."))
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        LabeledContent {
                            Text(Locale.current.localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "de")?.localizedCapitalized ?? "")
                        } label: {
                            Label("Sprache", systemImage: "globe")
                        }
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        SecurityInfoView()
                    } label: {
                        Label("So schützt Krypta dich", systemImage: "lock.shield")
                    }
                }

                Section {
                    Button(role: .destructive) { confirmWipe = true } label: {
                        Label("Alles löschen", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Löscht Schlüssel, Chats und dein Konto auf dem Server. Deine Kontakte erfahren, dass es dich nicht mehr gibt.")
                }

                Section {
                } footer: {
                    Text("Krypta \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .sheet(isPresented: $showMyCode) { MyCodeView() }
            .task { await refreshPushPermission() }
            .sheet(isPresented: $setupCalculator) {
                CalculatorSetupSheet { secret, delete in
                    if (try? app.setCalculator(secret: secret, delete: delete)) != nil { calculator = true }
                    setupCalculator = false
                }
            }
            .confirmationDialog("Tarnung ausschalten?", isPresented: $confirmDisableCalculator, titleVisibility: .visible) {
                Button("Ausschalten", role: .destructive) {
                    app.disableCalculator()
                    calculator = false
                }
            } message: {
                Text("Geheim- und Löschcode werden entfernt.")
            }
            .confirmationDialog("Alles löschen?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Alles löschen", role: .destructive) {
                    Task { await app.emergencyWipe() }
                }
            } message: {
                Text("Das lässt sich nicht rückgängig machen.")
            }
        }
    }
}

extension SettingsView {
    private func refreshPushPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        pushDenied = status == .denied
    }
}

/// Tresor-Passwort festlegen, ändern oder entfernen.
private struct VaultPasswordSettings: View {
    @Binding var isSet: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var error: String?
    @State private var working = false
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section {
                if isSet {
                    SecureField("Aktuelles Passwort", text: $current)
                        .textContentType(.password)
                }
                SecureField(isSet ? "Neues Passwort" : "Passwort", text: $new)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("vault.new")
                SecureField("Wiederholen", text: $repeated)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("vault.repeat")
            } footer: {
                Text("Nach Rechner-Code und \(Biometrics.name) fragt Krypta nach diesem Passwort. Wer es fünfmal falsch eingibt, löscht alles — wie mit dem Löschcode. Mindestens \(VaultPassword.minimumLength) Zeichen.")
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button(isSet ? "Passwort ändern" : "Passwort festlegen", action: save)
                    .disabled(working || new.isEmpty || repeated.isEmpty || (isSet && current.isEmpty))
                    .accessibilityIdentifier("vault.save")
                if isSet {
                    Button("Passwort entfernen", role: .destructive) { confirmRemove = true }
                        .disabled(working || current.isEmpty)
                }
            }
        }
        .navigationTitle("Tresor-Passwort")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Tresor-Passwort entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                Task {
                    guard await checkCurrent() else { return }
                    VaultPassword.remove()
                    isSet = false
                    dismiss()
                }
            }
        }
    }

    private func checkCurrent() async -> Bool {
        guard isSet, let stored = Keychain.string(.vaultPassword) else { return true }
        let input = current
        working = true
        let ok = await Task.detached(priority: .userInitiated) { AccessCodes.verify(input, against: stored) }.value
        working = false
        if !ok { error = String(localized: "Das aktuelle Passwort stimmt nicht.") }
        return ok
    }

    private func save() {
        error = nil
        guard new.count >= VaultPassword.minimumLength else {
            error = String(localized: "Das Passwort braucht mindestens \(VaultPassword.minimumLength) Zeichen.")
            return
        }
        guard new == repeated else {
            error = String(localized: "Die Passwörter stimmen nicht überein.")
            return
        }
        Task {
            guard await checkCurrent() else { return }
            working = true
            do {
                try await VaultPassword.set(new)
                isSet = true
                dismiss()
            } catch {
                self.error = String(localized: "Das Passwort konnte nicht gespeichert werden.")
            }
            working = false
        }
    }
}

/// Codes für die Tarnung nachträglich einrichten.
private struct CalculatorSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let done: (String, String) -> Void
    @State private var secret: String?

    var body: some View {
        NavigationStack {
            Group {
                if let secret {
                    PasscodeEntryView(
                        title: "Löschcode festlegen",
                        message: "Im Notfall: dieser Code + = löscht sofort alles — ohne Rückfrage.",
                        symbol: "trash.fill", tint: .red
                    ) { code in
                        guard code != secret else { return String(localized: "Der Löschcode muss sich vom Geheimcode unterscheiden.") }
                        done(secret, code)
                        return nil
                    }
                    .id("delete")
                } else {
                    PasscodeEntryView(
                        title: "Geheimcode festlegen",
                        message: "Gib diesen Code im Rechner ein und tippe auf =, um Krypta zu öffnen.",
                        symbol: "lock.fill", tint: .accentColor
                    ) { code in
                        secret = code
                        return nil
                    }
                    .id("secret")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }
}

/// Was Krypta tut, in einfachen Worten.
private struct SecurityInfoView: View {
    var body: some View {
        List {
            item("lock.fill", "Ende-zu-Ende-Verschlüsselung",
                 "Jede Nachricht hat ihren eigenen Schlüssel (Signal-Protokoll: X3DH und Double Ratchet). Wer einen davon erbeutet, liest damit nur diese eine Nachricht — frühere bleiben geschützt.")
            item("person.fill.questionmark", "Versteckter Absender",
                 "Wer dir schreibt, steht verschlüsselt in der Nachricht. Der Server sieht nur, dass etwas für dich ankommt.")
            item("text.alignleft", "Gleich lange Nachrichten",
                 "Nachrichten werden auf feste Größen aufgefüllt, damit man an der Länge nichts ablesen kann.")
            item("checkmark.seal", "Sicherheitsnummer",
                 "Stimmt die Nummer auf beiden Geräten überein, sitzt niemand dazwischen. Ändert sie sich, sperrt Krypta den Chat, bis ihr sie neu vergleicht.")
            item("internaldrive", "Nichts im Klartext auf dem Gerät",
                 "Chats und Schlüssel liegen verschlüsselt auf dem iPhone, der Schlüssel dazu im Schlüsselbund. Nichts davon landet in Backups.")
            item("icloud.slash", "Der Server vergisst",
                 "Nachrichten liegen nur so lange auf dem Server, bis dein Gerät sie abholt.")
        }
        .navigationTitle("So schützt Krypta dich")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
