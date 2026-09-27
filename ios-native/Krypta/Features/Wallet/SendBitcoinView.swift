import KryptaBitcoin
import KryptaMessenger
import KryptaWallet
import SwiftUI

/// Bitcoin senden: an einen Kontakt im Chat oder an eine Adresse.
struct SendBitcoinView: View {
    enum Target: Equatable {
        /// Im Chat: an die Adresse, die der Kontakt verschlüsselt geschickt hat.
        case contact(chatId: String, contactId: String)
        /// Irgendwohin: Adresse eintippen, einfügen oder scannen.
        case address
    }

    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeSheet) private var closeSheet
    /// Eine Bitte aus dem Chat: der Betrag steht fest, die Notiz ist vorbelegt.
    struct Answering: Identifiable, Equatable {
        let messageId: String
        let sats: Int64
        let note: String
        var id: String { messageId }
    }

    let target: Target
    var answering: Answering?
    /// Nach dem Senden (schließt auch das Blatt darunter).
    var onSent: () -> Void = {}

    @State private var addressText = ""
    @State private var amountText = ""
    @State private var inSats = false
    @State private var sendAll = false
    @State private var feeLevel: FeeLevel = .normal
    @State private var note = ""
    @State private var error: String?
    @State private var draft: DraftStep?
    @State private var scanning = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            if let wallet {
                form(wallet)
            } else {
                ContentUnavailableView("Keine Wallet", systemImage: "bitcoinsign.circle")
            }
        }
    }

    @ViewBuilder
    private func form(_ wallet: WalletEngine) -> some View {
        Form {
            Section {
                switch target {
                case .contact(_, let contactId):
                    if let contact = engine.contact(contactId), let chat = engine.chat(forContact: contactId) {
                        HStack(spacing: 12) {
                            Avatar(id: contact.id, name: chat.name, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: chat.name).font(.headline)
                                if let address = engine.paymentAddress(for: contactId) {
                                    Text(verbatim: BitcoinFormat.grouped(address.string))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                case .address:
                    HStack {
                        TextField("bc1q… oder bitcoin:…", text: $addressText, axis: .vertical)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(1...3)
                            .onChange(of: addressText) { parseRequest() }
                            .accessibilityIdentifier("wallet.send.address")
                        Button { scanning = true } label: { Image(systemName: "qrcode.viewfinder").font(.title3) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("QR-Code scannen")
                    }
                    if !addressText.isEmpty, recipient == nil {
                        Text(addressProblem).font(.footnote).foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Empfänger")
            } footer: {
                if case .contact = target {
                    Text("Die Adresse hat dein Kontakt verschlüsselt im Chat geschickt, nur für dich. Jede Zahlung geht an eine neue.")
                }
            }

            amountSection(wallet)

            Section {
                if let fees = wallet.feeEstimates {
                    Picker("Gebühr", selection: $feeLevel) {
                        feeRow("Schnell", "etwa 20 Minuten", fees.fast).tag(FeeLevel.fast)
                        feeRow("Normal", "etwa 1 Stunde", fees.normal).tag(FeeLevel.normal)
                        feeRow("Günstig", "einige Stunden", fees.slow).tag(FeeLevel.slow)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } else {
                    HStack {
                        ProgressView()
                        Text("Gebühren werden geladen …").foregroundStyle(.secondary)
                    }
                    .task { await wallet.sync() }
                }
            } header: {
                Text("Gebühr")
            } footer: {
                Text("Die Gebühr bekommen die Miner, nicht Krypta. Höher heißt schneller im Block.")
            }

            if case .contact = target {
                Section("Notiz") {
                    TextField("Wofür? (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                Button {
                    prepare(wallet)
                } label: {
                    Text("Weiter").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
                .disabled(recipient == nil || (answering == nil && !sendAll && amountSats == nil) || wallet.feeEstimates == nil)
                .accessibilityIdentifier("wallet.send.next")
            }
        }
        .navigationTitle("Bitcoin senden")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { close() } }
            if case .address = target {
                ToolbarItem(placement: .topBarTrailing) {
                    // Ohne Rückfrage von iOS: der Knopf selbst ist die Erlaubnis.
                    PasteButton(payloadType: String.self) { strings in
                        if let text = strings.first { addressText = text }
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .navigationDestination(item: $draft) { step in
            ConfirmPaymentView(draft: step.draft, target: target, answering: answering?.messageId) {
                close()
                onSent()
            }
        }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScannerView { code in
                    addressText = code
                    scanning = false
                }
                .ignoresSafeArea()
                .navigationTitle("Bitcoin-Adresse scannen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { scanning = false } } }
            }
        }
        .onChange(of: feeLevel) { error = nil }
        .onAppear {
            if let answering, note.isEmpty { note = answering.note }
        }
    }

    /// Der Betrag: eingetippt, oder auf eine Bitte hin fest.
    @ViewBuilder
    private func amountSection(_ wallet: WalletEngine) -> some View {
        if let answering {
            Section {
                LabeledContent("Erbeten") {
                    Text(verbatim: BitcoinFormat.btc(answering.sats)).font(.title3.weight(.semibold)).monospacedDigit()
                }
                if let fiat = BitcoinFormat.fiat(answering.sats, rate: wallet.fiatRate) {
                    Text(verbatim: fiat).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Betrag")
            } footer: {
                Text("Verfügbar: \(BitcoinFormat.btc(wallet.balance.spendable))")
            }
        } else {
            Section {
                if sendAll {
                    HStack {
                        Text("Alles, abzüglich Gebühr")
                        Spacer()
                        Button("Ändern") { sendAll = false; amountFocused = true }.buttonStyle(.borderless)
                    }
                } else {
                    HStack {
                        TextField(inSats ? "0" : "0" + BitcoinFormat.decimalSeparator + "00", text: $amountText)
                            .keyboardType(inSats ? .numberPad : .decimalPad)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .focused($amountFocused)
                            .accessibilityIdentifier("wallet.send.amount")
                        Picker("Einheit", selection: $inSats) {
                            Text(verbatim: "BTC").tag(false)
                            Text(verbatim: "sat").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                        .onChange(of: inSats) { _, sats in convertAmount(toSats: sats) }
                    }
                    if let sats = amountSats, let fiat = BitcoinFormat.fiat(sats, rate: wallet.fiatRate) {
                        Text(verbatim: fiat).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Alles senden") { sendAll = true; amountFocused = false }
                }
            } header: {
                Text("Betrag")
            } footer: {
                Text("Verfügbar: \(BitcoinFormat.btc(wallet.balance.spendable))")
            }
        }
    }

    /// Das Blatt schließen, auch aus dem Screenshot-Schutz heraus.
    private func close() {
        if let closeSheet { closeSheet() } else { dismiss() }
    }

    private func feeRow(_ title: LocalizedStringKey, _ time: LocalizedStringKey, _ rate: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(time).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: BitcoinFormat.feeRate(rate)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    // MARK: - Eingaben

    private var recipient: BitcoinAddress? {
        guard let wallet else { return nil }
        switch target {
        case .contact(_, let contactId):
            return engine.paymentAddress(for: contactId)
        case .address:
            return try? PaymentRequest.parse(addressText, network: wallet.network).address
        }
    }

    private var addressProblem: String {
        guard let wallet else { return "" }
        do {
            _ = try PaymentRequest.parse(addressText, network: wallet.network)
            return ""
        } catch BitcoinError.wrongNetwork {
            return BitcoinFormat.message(.wrongNetwork) ?? ""
        } catch BitcoinError.unsupportedAddress {
            return String(localized: "Diese Art Adresse unterstützt Krypta nicht.")
        } catch {
            return BitcoinFormat.message(.invalidAddress) ?? ""
        }
    }

    /// Ein `bitcoin:`-Link mit Betrag füllt den Betrag aus.
    private func parseRequest() {
        error = nil
        guard let wallet, let request = try? PaymentRequest.parse(addressText, network: wallet.network) else { return }
        if addressText != request.address.string && request.amount == nil {
            addressText = request.address.string
        }
        if let amount = request.amount {
            addressText = request.address.string
            sendAll = false
            inSats = false
            amountText = BitcoinAmount.plainBTC(amount).replacingOccurrences(of: ".", with: BitcoinFormat.decimalSeparator)
        }
    }

    private var amountSats: Int64? {
        let parsed = inSats ? BitcoinAmount.parseSats(amountText) : BitcoinAmount.parse(amountText)
        guard let parsed, parsed > 0 else { return nil }
        return parsed
    }

    private func convertAmount(toSats: Bool) {
        let old = toSats ? BitcoinAmount.parse(amountText) : BitcoinAmount.parseSats(amountText)
        guard let old else { return }
        amountText = toSats ? String(old) : BitcoinAmount.plainBTC(old).replacingOccurrences(of: ".", with: BitcoinFormat.decimalSeparator)
    }

    private func prepare(_ wallet: WalletEngine) {
        error = nil
        guard let recipient else { return }
        let amount: TransactionPlanner.Amount
        if let answering {
            amount = .exact(answering.sats)
        } else if sendAll {
            amount = .all
        } else {
            guard let sats = amountSats else { return }
            amount = .exact(sats)
        }
        var contactId: String?
        if case .contact(_, let id) = target { contactId = id }
        do {
            draft = DraftStep(draft: try wallet.prepare(to: recipient, amount: amount, feeLevel: feeLevel, contactId: contactId,
                                                        note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        } catch let failure as WalletFailure {
            error = BitcoinFormat.message(failure)
            Haptics.error()
        } catch {
            self.error = BitcoinFormat.message(.signingFailed)
        }
    }
}

/// Ein Entwurf als Navigationsziel.
struct DraftStep: Hashable {
    let id = UUID()
    let draft: PaymentDraft

    static func == (a: DraftStep, b: DraftStep) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Letzter Blick vor dem Senden. Bitcoin lässt sich nicht zurückholen.
struct ConfirmPaymentView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(MessengerEngine.self) private var engine
    let draft: PaymentDraft
    let target: SendBitcoinView.Target
    /// Die Bitte, die damit bezahlt wird.
    var answering: String?
    let done: () -> Void

    @State private var sending = false
    @State private var error: String?
    @State private var confirmHighFee = false
    @State private var sent = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text(verbatim: BitcoinFormat.btc(draft.amount))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let fiat = BitcoinFormat.fiat(draft.amount, rate: wallet?.fiatRate) {
                        Text(verbatim: fiat).foregroundStyle(.secondary)
                    }
                    NetworkBadge(network: draft.recipient.network)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section("Empfänger") {
                if case .contact(_, let contactId) = target, let chat = engine.chat(forContact: contactId) {
                    LabeledContent("Kontakt") { Text(verbatim: chat.name) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adresse").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: BitcoinFormat.grouped(draft.recipient.string))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("wallet.confirm.address")
                }
            }

            Section {
                LabeledContent("Betrag") { Text(verbatim: BitcoinFormat.btc(draft.amount)).monospacedDigit() }
                LabeledContent("Gebühr") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: BitcoinFormat.sats(draft.fee)).monospacedDigit()
                        Text(verbatim: BitcoinFormat.feeRate(draft.plan.feeRate)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Gesamt") { Text(verbatim: BitcoinFormat.btc(draft.total)).fontWeight(.semibold).monospacedDigit() }
                if let note = draft.note {
                    LabeledContent("Notiz") { Text(verbatim: note) }
                }
            } footer: {
                if draft.feeShare > 0.1 {
                    Label("Die Gebühr ist mehr als 10 % des Betrags.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                Button {
                    if draft.feeShare > 0.1 { confirmHighFee = true } else { Task { await send() } }
                } label: {
                    HStack {
                        Spacer()
                        if sending { ProgressView() } else {
                            Label("Senden", systemImage: Biometrics.symbol)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(sending || sent)
                .accessibilityIdentifier("wallet.confirm.send")
            } footer: {
                Text("Bitcoin-Zahlungen lassen sich nicht zurückholen. Prüfe Empfänger und Betrag. Zum Senden fragt Krypta nach \(Biometrics.name) oder deinem Gerätecode.")
            }
        }
        .navigationTitle("Prüfen und senden")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(sending)
        .navigationBarBackButtonHidden(sending)
        .confirmationDialog("Hohe Gebühr", isPresented: $confirmHighFee, titleVisibility: .visible) {
            Button("Trotzdem senden") { Task { await send() } }
        } message: {
            Text("Du zahlst \(BitcoinFormat.sats(draft.fee)) Gebühr für \(BitcoinFormat.btc(draft.amount)).")
        }
        .sensoryFeedback(.success, trigger: sent)
    }

    private func send() async {
        guard let wallet, !sending else { return }
        sending = true
        error = nil
        defer { sending = false }
        let reason = String(localized: "Bitcoin senden")
        do {
            switch target {
            case .contact(let chatId, _):
                _ = try await engine.pay(chatId: chatId, draft: draft, reason: reason, answering: answering)
            case .address:
                _ = try await wallet.send(draft, reason: reason)
            }
            sent = true
            try? await Task.sleep(for: .milliseconds(400))
            done()
        } catch let failure as WalletFailure {
            error = BitcoinFormat.message(failure)
            if error != nil { Haptics.error() }
        } catch {
            self.error = BitcoinFormat.message(.signingFailed)
            Haptics.error()
        }
    }
}
