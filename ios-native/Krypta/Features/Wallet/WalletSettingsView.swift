import KryptaBitcoin
import KryptaWallet
import SwiftUI

/// Einstellungen der Wallet.
struct WalletSettingsView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(AppModel.self) private var app

    @State private var showBackup = false
    @State private var showRestore = false
    @State private var server = ""
    @State private var serverSaved = false
    @State private var scanning = false

    var body: some View {
        Form {
            if let wallet {
                Section {
                    Toggle(isOn: Binding(get: { wallet.chatPaymentsEnabled }, set: { wallet.chatPaymentsEnabled = $0 })) {
                        SettingsLabel("Zahlungen im Chat", symbol: "bitcoinsign.circle.fill", color: .orange)
                    }
                } footer: {
                    Text(wallet.chatPaymentsEnabled
                         ? "Kontakte mit Krypta bekommen verschlüsselt eine Adresse, die nur für sie ist, und können dich direkt im Chat bezahlen. Der Server von Krypta sieht davon nichts."
                         : "Niemand bekommt eine Adresse von dir, und niemand kann dich im Chat bezahlen. Empfangen über den QR-Code geht weiter.")
                }

                Section {
                    Button { showBackup = true } label: {
                        SettingsRow("Wiederherstellungswörter", symbol: "key.horizontal.fill", color: .orange)
                    }
                    .foregroundStyle(.primary)
                    Button { showRestore = true } label: {
                        SettingsRow("Wallet wiederherstellen", symbol: "arrow.counterclockwise", color: .gray)
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Sicherung")
                } footer: {
                    Text(wallet.backedUp ? "Gesichert. Bewahre den Zettel gut auf." : "Noch nicht gesichert. Ohne die Wörter ist dein Bitcoin weg, wenn Krypta alles löscht oder das iPhone verloren geht.")
                }

                protection

                Section {
                    TextField("https://mempool.space/api/", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                    Button(serverSaved ? "Übernommen" : "Übernehmen") {
                        WalletSettings.setServer(server.isEmpty ? nil : server, for: wallet.network)
                        server = WalletSettings.customServer(for: wallet.network) ?? ""
                        serverSaved = true
                        app.reloadWallet()
                    }
                    .disabled(!server.isEmpty && WalletSettings.validServer(server) == nil)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Leer: mempool.space. Der Server sieht, welche Adressen deine Wallet abfragt, und deine IP-Adresse, aber nie deine Schlüssel, und er kann keine Zahlung vortäuschen: Krypta prüft jede selbst. Wer einen eigenen Knoten mit Esplora betreibt, trägt ihn hier ein (nur https).")
                }

                if WalletSettings.selectable.contains(wallet.network) {
                    Section {
                        Picker("Netz", selection: Binding(get: { wallet.network }, set: { network in
                            WalletSettings.network = network
                            server = WalletSettings.customServer(for: network) ?? ""
                            app.reloadWallet()
                        })) {
                            ForEach(WalletSettings.selectable, id: \.self) { n in
                                Text(verbatim: BitcoinFormat.networkName(n)).tag(n)
                            }
                        }
                    } header: {
                        Text("Netz")
                    } footer: {
                        Text("Testnet4 und Signet sind Spielgeld zum Ausprobieren, mit denselben zwölf Wörtern. Beide Seiten eines Chats müssen dasselbe Netz nutzen.")
                    }
                }

                Section {
                    Button {
                        Task { await wallet.deepSync() }
                    } label: {
                        HStack {
                            Text("Adressen gründlich durchsuchen")
                            Spacer()
                            if wallet.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(wallet.isSyncing)
                } footer: {
                    Text("Sucht 200 Adressen tief. Nur nötig, wenn nach dem Wiederherstellen Guthaben fehlt.")
                }
            }
        }
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let wallet { server = WalletSettings.customServer(for: wallet.network) ?? "" }
        }
        .sheet(isPresented: $showBackup) { ShieldedSheet(always: true) { BackupView() } }
        .sheet(isPresented: $showRestore) { ShieldedSheet(always: true) { RestoreWalletView() } }
    }

    /// Im Demo liegt der Schlüssel im Speicher, nicht im Schlüsselbund.
    private var isDemo: Bool {
        #if DEBUG
        return DemoMode.isActive || DemoMode.isOffline
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var protection: some View {
        if !isDemo {
            Section {
                if WalletKeychain.shared.isProtectedByDeviceAuth {
                    LabeledContent {
                        Text(verbatim: Biometrics.available == .none ? String(localized: "Gerätecode") : Biometrics.name)
                    } label: {
                        SettingsLabel("Senden nur mit", symbol: "lock.shield.fill", color: .green)
                    }
                } else {
                    Label("Dein iPhone hat keinen Gerätecode. Dann kann Krypta das Senden nicht an Face ID binden: wer dein entsperrtes iPhone hat, kann Bitcoin senden. Richte in den iOS-Einstellungen einen Code ein.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            } header: {
                Text("Schutz")
            } footer: {
                Text("Der Schlüssel liegt im Schlüsselbund nur dieses iPhones, nicht in Backups und nicht in iCloud. Selbst Krypta kommt ohne deine Bestätigung nicht an ihn heran.")
            }
        }
    }
}

/// Eine Wallet aus zwölf (bis 24) Wörtern wiederherstellen.
struct RestoreWalletView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeSheet) private var closeSheet

    @State private var text = ""
    @State private var confirmReplace = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditorBox(text: $text)
                        .frame(height: 150)
                    if let last = currentWord, !Mnemonic.isWord(last) {
                        let options = Mnemonic.suggestions(for: last)
                        if !options.isEmpty {
                            HStack {
                                ForEach(options, id: \.self) { word in
                                    Button(word) { complete(word) }
                                        .buttonStyle(.bordered)
                                        .font(.callout.monospaced())
                                }
                            }
                        }
                    }
                } header: {
                    Text("Wörter")
                } footer: {
                    Text(status)
                        .foregroundStyle(parsed != nil ? .green : .secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        confirmReplace = true
                    } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text("Wiederherstellen").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(parsed == nil || working)
                } footer: {
                    Text("Ersetzt die Wallet auf diesem iPhone. Wörter einer anderen Wallet (BIP39, BIP84, native Segwit) funktionieren auch.")
                }
            }
            .navigationTitle("Wiederherstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { text = ""; close() } } }
            .confirmationDialog("Wallet ersetzen?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Ersetzen", role: .destructive) { Task { await restore() } }
            } message: {
                Text(replaceWarning)
            }
        }
    }

    private var words: [String] {
        text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "," }).map(String.init)
    }

    private var currentWord: String? {
        guard let last = text.last, last != " ", last != "\n" else { return nil }
        return words.last
    }

    private var parsed: [String]? {
        (try? Mnemonic.entropy(words: words)) == nil ? nil : words
    }

    private var status: String {
        let count = words.count
        if let bad = words.firstIndex(where: { !Mnemonic.isWord($0) }), bad < count - 1 || currentWord == nil {
            return String(localized: "Wort \(bad + 1) gibt es in der Liste nicht.")
        }
        if parsed != nil { return String(localized: "\(count) Wörter, Prüfsumme stimmt.") }
        if Mnemonic.validWordCounts.contains(count), currentWord == nil || Mnemonic.isWord(words.last ?? "") {
            return String(localized: "Die Prüfsumme stimmt nicht. Ist ein Wort vertauscht?")
        }
        return String(localized: "\(count) von 12 Wörtern")
    }

    private var replaceWarning: String {
        guard let wallet, wallet.balance.total > 0 || !wallet.backedUp else {
            return String(localized: "Die jetzige Wallet wird durch die aus diesen Wörtern ersetzt.")
        }
        return String(localized: "Die jetzige Wallet wird ersetzt. Ohne ihre eigenen Wörter ist ihr Guthaben danach verloren.")
    }

    /// Das Blatt schließen, auch aus dem Screenshot-Schutz heraus.
    private func close() {
        if let closeSheet { closeSheet() } else { dismiss() }
    }

    private func complete(_ word: String) {
        var list = words
        guard !list.isEmpty else { return }
        list[list.count - 1] = word
        text = list.joined(separator: " ") + " "
    }

    private func restore() async {
        guard let list = parsed else { return }
        working = true
        defer { working = false }
        do {
            try await app.restoreWallet(words: list)
            text = ""
            Haptics.success()
            close()
        } catch {
            Haptics.error()
            self.error = String(localized: "Die Wörter konnten nicht übernommen werden.")
        }
    }
}

/// Ein Textfeld ohne Rechtschreibhilfe und ohne Vorschläge der Tastatur.
private struct TextEditorBox: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("restore.words")
    }
}
