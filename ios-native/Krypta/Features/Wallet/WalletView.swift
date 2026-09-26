import KryptaBitcoin
import KryptaMessenger
import KryptaWallet
import SwiftUI

/// Die Bitcoin-Wallet: Guthaben, Empfangen, Senden, Verlauf.
struct WalletView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeSheet) private var closeSheet

    @State private var showReceive = false
    @State private var showSend = false
    @State private var showBackup = false

    var body: some View {
        NavigationStack {
            Group {
                if let wallet {
                    content(wallet)
                } else {
                    ContentUnavailableView {
                        Label("Keine Wallet", systemImage: "bitcoinsign.circle")
                    } description: {
                        Text("Die Wallet konnte nicht geöffnet werden. Öffne Krypta noch einmal.")
                    }
                }
            }
            .navigationTitle("Bitcoin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { close() } }
                if wallet != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            WalletSettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Wallet-Einstellungen")
                    }
                }
            }
        }
    }

    /// Das Blatt schließen, auch aus dem Screenshot-Schutz heraus.
    private func close() {
        if let closeSheet { closeSheet() } else { dismiss() }
    }

    @ViewBuilder
    private func content(_ wallet: WalletEngine) -> some View {
        List {
            Section {
                VStack(spacing: 8) {
                    NetworkBadge(network: wallet.network)
                    Text(verbatim: BitcoinFormat.balance(wallet.balance.spendable))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel(Text(verbatim: BitcoinFormat.btc(wallet.balance.spendable)))
                        .accessibilityIdentifier("wallet.balance")
                    Text(verbatim: "BTC").font(.headline).foregroundStyle(.secondary)
                    if let fiat = BitcoinFormat.fiat(wallet.balance.spendable, rate: wallet.fiatRate) {
                        Text(verbatim: fiat).foregroundStyle(.secondary)
                    }
                    if wallet.balance.incoming > 0 {
                        Label("\(BitcoinFormat.btc(wallet.balance.incoming, sign: true)) unterwegs", systemImage: "hourglass")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 12) {
                        Button { showReceive = true } label: {
                            Label("Empfangen", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("wallet.receive")
                        Button { showSend = true } label: {
                            Label("Senden", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity)
                        }
                        .disabled(wallet.balance.spendable == 0)
                        .accessibilityIdentifier("wallet.send")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            if !wallet.backedUp {
                Section {
                    Button { showBackup = true } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Wiederherstellungswörter sichern").font(.headline).foregroundStyle(.primary)
                                Text("Ohne diese zwölf Wörter ist dein Bitcoin weg, wenn das iPhone verloren geht oder Krypta alles löscht (Löschcode, Notfallknopf, fünfmal falsches Passwort).")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("wallet.backup")
                }
            }

            if let error = wallet.lastError, let text = BitcoinFormat.message(error) {
                Section {
                    Label(text, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                if wallet.transactions.isEmpty {
                    Text(wallet.isSyncing ? "Wird abgeglichen …" : "Noch keine Zahlungen.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(wallet.transactions) { tx in
                        NavigationLink {
                            TransactionDetailView(txid: tx.txid)
                        } label: {
                            TransactionRow(tx: tx, name: tx.contactId.flatMap { engine.chat(forContact: $0)?.name }, tip: wallet.tipHeight)
                        }
                    }
                }
            } header: {
                Text("Verlauf")
            } footer: {
                if let last = wallet.lastSync {
                    Text("Abgeglichen \(last.formatted(.relative(presentation: .named)))")
                }
            }
        }
        .refreshable { await wallet.sync() }
        .task { await wallet.sync() }
        .sheet(isPresented: $showReceive) { ShieldedSheet { ReceiveView() } }
        .sheet(isPresented: $showSend) { ShieldedSheet { SendBitcoinView(target: .address) } }
        .sheet(isPresented: $showBackup) { ShieldedSheet(always: true) { BackupView() } }
    }
}

/// Eine Zeile im Verlauf.
struct TransactionRow: View {
    let tx: WalletTransaction
    let name: String?
    let tip: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tx.isIncoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(tx.isIncoming ? Color.green : Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.body.weight(.medium)).lineLimit(1)
                Text(verbatim: subtitle).font(.caption).foregroundStyle(tx.outgoing == .failed || tx.outgoing == .uncertain ? .red : .secondary)
            }
            Spacer()
            Text(verbatim: BitcoinFormat.btc(tx.net, sign: true))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(tx.isIncoming ? Color.green : Color.primary)
                .strikethrough(tx.outgoing == .failed)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let name { return tx.isIncoming ? String(localized: "Von \(name)") : String(localized: "An \(name)") }
        return tx.isIncoming ? String(localized: "Empfangen") : String(localized: "Gesendet")
    }

    private var subtitle: String {
        let date = tx.time.formatted(date: .abbreviated, time: .shortened)
        switch tx.outgoing {
        case .failed?: return String(localized: "Nicht gesendet")
        case .uncertain?: return String(localized: "Unklar, Krypta prüft")
        case .broadcasting?: return String(localized: "Wird gesendet …")
        default: break
        }
        guard tx.isConfirmed else { return String(localized: "\(date) · unbestätigt") }
        let n = tx.confirmations(tip: tip)
        return n >= 6 ? date : String(localized: "\(date) · \(n) von 6 Bestätigungen")
    }
}

/// Eine Transaktion im Einzelnen.
struct TransactionDetailView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(MessengerEngine.self) private var engine
    let txid: String

    var body: some View {
        List {
            if let wallet, let tx = wallet.transactions.first(where: { $0.txid == txid }) {
                Section {
                    LabeledContent(tx.isIncoming ? "Erhalten" : "Gesendet") {
                        Text(verbatim: BitcoinFormat.btc(tx.net.magnitude > 0 ? Int64(tx.net.magnitude) : 0)).monospacedDigit()
                    }
                    if let fee = tx.fee, !tx.isIncoming {
                        LabeledContent("Davon Gebühr") { Text(verbatim: BitcoinFormat.sats(fee)).monospacedDigit() }
                    }
                    if let id = tx.contactId, let chat = engine.chat(forContact: id) {
                        LabeledContent(tx.isIncoming ? "Absender" : "Empfänger") { Text(verbatim: chat.name) }
                    }
                    if let note = tx.note, !note.isEmpty {
                        LabeledContent("Notiz") { Text(verbatim: note) }
                    }
                    LabeledContent("Zeit") { Text(tx.time, format: .dateTime) }
                    LabeledContent("Bestätigungen") {
                        Text(verbatim: tx.isConfirmed ? String(tx.confirmations(tip: wallet.tipHeight)) : "0")
                    }
                }
                Section {
                    Button {
                        SecurePasteboard.copy(tx.txid, lifetime: SecurePasteboard.idLifetime)
                        Haptics.confirm()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transaktion").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: tx.txid).font(.caption.monospaced()).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Label("Kopieren", systemImage: "doc.on.doc").font(.caption)
                        }
                    }
                    if let url = wallet.network.explorerURL(txid: tx.txid) {
                        Link(destination: url) { Label("Im Block-Explorer ansehen", systemImage: "safari") }
                    }
                } footer: {
                    if tx.outgoing == .uncertain {
                        Text("Die Verbindung brach beim Senden ab. Krypta sendet bei jedem Abgleich genau diese Transaktion erneut, bis sie auf der Blockchain ist. Eine zweite Zahlung entsteht dabei nie.")
                    }
                }
            }
        }
        .navigationTitle("Transaktion")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Die eigene Adresse als QR-Code.
struct ReceiveView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeSheet) private var closeSheet
    @State private var address: BitcoinAddress?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let wallet, let address {
                    NetworkBadge(network: wallet.network)
                    if let image = QRImage.make("bitcoin:" + address.string.uppercased()) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .frame(maxWidth: 280)
                            .accessibilityLabel("QR-Code deiner Bitcoin-Adresse")
                    }
                    Text(verbatim: BitcoinFormat.grouped(address.string))
                        .font(.body.monospaced())
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier("wallet.receive.address")
                    HStack(spacing: 12) {
                        Button {
                            SecurePasteboard.copy(address.string, lifetime: SecurePasteboard.idLifetime)
                            copied = true
                        } label: {
                            Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        ShareLink(item: address.string) { Label("Teilen", systemImage: "square.and.arrow.up") }
                    }
                    .buttonStyle(.bordered)
                    .sensoryFeedback(.success, trigger: copied)
                    Button("Neue Adresse") {
                        self.address = wallet.newReceiveAddress()
                        copied = false
                    }
                    .font(.footnote)
                    Spacer()
                    Text("Nur Bitcoin (\(BitcoinFormat.networkName(wallet.network))) an diese Adresse senden. Sobald etwas eingeht, zeigt Krypta eine neue, damit deine Zahlungen nicht miteinander verknüpft werden. Kontakte im Chat bekommen ohnehin jeder ihre eigene.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 12)
            .navigationTitle("Empfangen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { close() } } }
            .onAppear { address = wallet?.receiveAddress() }
        }
    }

    /// Das Blatt schließen, auch aus dem Screenshot-Schutz heraus.
    private func close() {
        if let closeSheet { closeSheet() } else { dismiss() }
    }
}
