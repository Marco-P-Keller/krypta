import KryptaMessenger
import SwiftUI

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
                    Toggle(isOn: $engine.readReceiptsEnabled) {
                        Label("Lesebestätigungen", systemImage: "checkmark.message")
                    }
                    Toggle(isOn: $engine.chatPreviewEnabled) {
                        Label("Vorschau in der Chatliste", systemImage: "text.bubble")
                    }
                } header: {
                    Text("Datenschutz")
                } footer: {
                    Text("Zustellungen werden immer gemeldet, weil an ihnen der Start der Löschfristen hängt. Lesebestätigungen nur, wenn du sie einschaltest.")
                }

                Section {
                    Toggle(isOn: Binding(get: { calculator }, set: { on in
                        if on { setupCalculator = true } else { confirmDisableCalculator = true }
                    })) {
                        Label("Als Rechner tarnen", systemImage: "plus.forwardslash.minus")
                    }
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
                         : "Ohne Tarnung öffnet sich Krypta direkt\(biometric ? " nach \(Biometrics.name)" : "").")
                }

                Section {
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
