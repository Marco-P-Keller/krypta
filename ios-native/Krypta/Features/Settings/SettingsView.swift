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
    @State private var changeCode: AccessCodes.Kind?
    @State private var codeChanged = false
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
                            Avatar(id: engine.userId, name: "User \(engine.userId)", size: 60)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Meine Kennung").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                Text(engine.userId).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                Text("QR-Code zeigen und teilen").font(.caption).foregroundStyle(.tint)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "qrcode").font(.title2).foregroundStyle(.tint)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.mycode")
                }

                Section {
                    Toggle(isOn: Binding(get: { push }, set: { on in
                        push = on
                        Task {
                            await PushService.shared.setEnabled(on, engine: engine)
                            await refreshPushPermission()
                        }
                    })) {
                        SettingsLabel("Mitteilungen", symbol: "bell.badge.fill", color: .red)
                    }
                    .accessibilityIdentifier("settings.push")
                    if push {
                        Toggle(isOn: Binding(get: { pushNames }, set: { on in
                            pushNames = on
                            PushService.showsNames = on
                            PushService.shared.updateIndex(engine)
                        })) {
                            SettingsLabel("Absender nennen", symbol: "person.crop.circle.fill", color: .orange)
                        }
                    }
                    if push && pushDenied {
                        Button {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        } label: {
                            SettingsLabel("In den iOS-Einstellungen erlauben", symbol: "gearshape.fill", color: .gray)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Mitteilungen")
                } footer: {
                    Text(push && pushNames
                         ? "Auf dem Sperrbildschirm steht nur, wer dir geschrieben hat — mit dem Namen, den du dem Kontakt gegeben hast. Was in der Nachricht steht, erfahren weder die Mitteilung noch Apple oder Google."
                         : "Auf dem Sperrbildschirm steht nur „Neue Nachricht“ — ohne Absender und ohne Inhalt.")
                }

                Section {
                    Toggle(isOn: $engine.readReceiptsEnabled) {
                        SettingsLabel("Lesebestätigungen", symbol: "checkmark.message.fill", color: .blue)
                    }
                    Toggle(isOn: $engine.chatPreviewEnabled) {
                        SettingsLabel("Vorschau in der Chatliste", symbol: "text.bubble.fill", color: .green)
                    }
                    Toggle(isOn: Binding(get: { app.screenshotShield }, set: { app.screenshotShield = $0 })) {
                        SettingsLabel("Bildschirmfotos verhindern", symbol: "eye.slash.fill", color: .indigo)
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
                        SettingsLabel("Als Rechner tarnen", symbol: "plus.forwardslash.minus", color: .orange)
                    }
                    if calculator {
                        Button { changeCode = .secret } label: {
                            SettingsRow("Geheimcode ändern", symbol: "lock.fill", color: .gray)
                        }
                        .foregroundStyle(.primary)
                        Button { changeCode = .delete } label: {
                            SettingsRow("Löschcode ändern", symbol: "trash.fill", color: .red)
                        }
                        .foregroundStyle(.primary)
                    }
                    if Biometrics.available != .none {
                        Toggle(isOn: Binding(get: { biometric }, set: { on in
                            Task { if await app.setBiometric(on) { biometric = on } }
                        })) {
                            SettingsLabel(verbatim: Biometrics.name, symbol: Biometrics.symbol, color: .green)
                        }
                    }
                    NavigationLink {
                        VaultPasswordSettings(isSet: $vaultPassword)
                    } label: {
                        LabeledContent {
                            Text(vaultPassword ? "An" : "Aus")
                        } label: {
                            SettingsLabel("Tresor-Passwort", symbol: "key.fill", color: .blue)
                        }
                    }
                    .accessibilityIdentifier("settings.vault")
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
                            SettingsLabel("Sprache", symbol: "globe", color: .blue)
                        }
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        SecurityInfoView()
                    } label: {
                        SettingsLabel("So schützt Krypta dich", symbol: "lock.shield.fill", color: .teal)
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        SettingsLabel("Datenschutzerklärung", symbol: "hand.raised.fill", color: .blue)
                    }
                    NavigationLink {
                        LicensesView()
                    } label: {
                        SettingsLabel("Open-Source-Lizenzen", symbol: "doc.text.fill", color: .gray)
                    }
                }

                Section {
                    Button(role: .destructive) { confirmWipe = true } label: {
                        Text("Alles löschen")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("settings.wipe")
                } footer: {
                    Text("Löscht Schlüssel, Chats und dein Konto auf dem Server. Deine Kontakte erfahren, dass es dich nicht mehr gibt.")
                }

                Section {
                } footer: {
                    Text("Krypta Chat \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await refreshPushPermission() }
            }
            .sheet(isPresented: $setupCalculator) {
                CalculatorSetupSheet { secret, delete in
                    if (try? app.setCalculator(secret: secret, delete: delete)) != nil { calculator = true }
                    setupCalculator = false
                }
            }
            .sheet(item: $changeCode) { kind in
                ChangeCodeSheet(kind: kind) {
                    changeCode = nil
                    codeChanged = true
                }
            }
            .sensoryFeedback(.success, trigger: codeChanged)
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

extension AccessCodes.Kind: Identifiable {
    var id: Self { self }
}

/// Symbol in einer farbigen Kachel, wie in der Einstellungen-App.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Titel mit Kachel — für Schalter und Verweise.
struct SettingsLabel: View {
    let title: Text
    let symbol: String
    let color: Color

    init(_ title: LocalizedStringKey, symbol: String, color: Color) {
        self.title = Text(title)
        self.symbol = symbol
        self.color = color
    }

    /// Für Namen, die nicht übersetzt werden (Face ID).
    init(verbatim title: String, symbol: String, color: Color) {
        self.title = Text(verbatim: title)
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label { title } icon: { SettingsIcon(symbol: symbol, color: color) }
    }
}

/// Zeile, die ein Blatt öffnet — mit Pfeil wie ein Verweis.
struct SettingsRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color

    init(_ title: LocalizedStringKey, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        HStack {
            SettingsLabel(title, symbol: symbol, color: color)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Geheim- oder Löschcode neu festlegen.
private struct ChangeCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: AccessCodes.Kind
    let done: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if kind == .secret {
                    PasscodeEntryView(
                        title: "Neuer Geheimcode",
                        message: "Gib diesen Code im Rechner ein und tippe auf =, um Krypta zu öffnen.",
                        symbol: "lock.fill", tint: .accentColor
                    ) { code in save(code) }
                } else {
                    PasscodeEntryView(
                        title: "Neuer Löschcode",
                        message: "Im Notfall: dieser Code + = löscht sofort alles — ohne Rückfrage.",
                        symbol: "trash.fill", tint: .red
                    ) { code in save(code) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }

    private func save(_ code: String) -> String? {
        do {
            guard try AccessCodes.change(kind, to: code) else {
                return String(localized: "Der Löschcode muss sich vom Geheimcode unterscheiden.")
            }
            done()
            return nil
        } catch {
            return String(localized: "Der Code konnte nicht gespeichert werden.")
        }
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

/// Die Datenschutzerklärung — derselbe Text wie in der Flutter-Fassung
/// (privacyPolicyBody in lib/l10n), in allen sieben Sprachen.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(String(localized: "privacy.policy.body"))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .navigationTitle("Datenschutzerklärung")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Fremder Code in Krypta und unter welcher Lizenz er steht.
struct LicensesView: View {
    private struct Library: Identifiable {
        let name: String
        let license: String
        let url: String
        var id: String { name }
    }

    private let libraries: [Library] = [
        .init(name: "libsodium", license: "ISC", url: "https://github.com/jedisct1/libsodium"),
        .init(name: "swift-sodium", license: "ISC", url: "https://github.com/jedisct1/swift-sodium"),
        .init(name: "Firebase iOS SDK", license: "Apache 2.0", url: "https://github.com/firebase/firebase-ios-sdk"),
        .init(name: "gRPC", license: "Apache 2.0", url: "https://github.com/grpc/grpc"),
        .init(name: "Abseil", license: "Apache 2.0", url: "https://github.com/abseil/abseil-cpp"),
        .init(name: "BoringSSL", license: "OpenSSL / ISC", url: "https://boringssl.googlesource.com/boringssl"),
        .init(name: "LevelDB", license: "BSD-3-Clause", url: "https://github.com/google/leveldb"),
        .init(name: "nanopb", license: "zlib", url: "https://github.com/nanopb/nanopb"),
        .init(name: "GoogleUtilities", license: "Apache 2.0", url: "https://github.com/google/GoogleUtilities"),
        .init(name: "GoogleDataTransport", license: "Apache 2.0", url: "https://github.com/google/GoogleDataTransport"),
        .init(name: "GTMSessionFetcher", license: "Apache 2.0", url: "https://github.com/google/gtm-session-fetcher"),
        .init(name: "Promises", license: "Apache 2.0", url: "https://github.com/google/promises"),
        .init(name: "App Check Core", license: "Apache 2.0", url: "https://github.com/google/app-check"),
        .init(name: "SwiftProtobuf", license: "Apache 2.0", url: "https://github.com/apple/swift-protobuf"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(libraries) { lib in
                    if let url = URL(string: lib.url) {
                        Link(destination: url) {
                            LabeledContent {
                                Text(lib.license)
                            } label: {
                                Text(verbatim: lib.name).foregroundStyle(.primary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Krypta verwendet diese Bibliotheken. Ihre Lizenztexte stehen in den verlinkten Quellen.")
            }
        }
        .navigationTitle("Open-Source-Lizenzen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
