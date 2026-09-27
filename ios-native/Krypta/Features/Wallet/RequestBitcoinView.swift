import KryptaBitcoin
import KryptaMessenger
import KryptaWallet
import SwiftUI

/// Einen Kontakt im Chat um Bitcoin bitten: Betrag und Notiz. Die eigene
/// Adresse reist verschlüsselt mit derselben Nachricht, nur für ihn.
struct RequestBitcoinView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeSheet) private var closeSheet
    let chatId: String
    let contactName: String

    @State private var amountText = ""
    @State private var inSats = false
    @State private var note = ""
    @State private var sending = false
    @State private var failed = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(inSats ? "0" : "0" + BitcoinFormat.decimalSeparator + "00", text: $amountText)
                            .keyboardType(inSats ? .numberPad : .decimalPad)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .focused($amountFocused)
                            .accessibilityIdentifier("wallet.request.amount")
                        Picker("Einheit", selection: $inSats) {
                            Text(verbatim: "BTC").tag(false)
                            Text(verbatim: "sat").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                        .onChange(of: inSats) { _, sats in convertAmount(toSats: sats) }
                    }
                    if let sats = amountSats, let fiat = BitcoinFormat.fiat(sats, rate: wallet?.fiatRate) {
                        Text(verbatim: fiat).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let wallet, wallet.network.isTest {
                        NetworkBadge(network: wallet.network)
                    }
                } header: {
                    Text("Betrag")
                } footer: {
                    Text("\(contactName) sieht Betrag und Notiz und kann mit einem Tippen bezahlen. Deine Adresse reist verschlüsselt mit, nur für \(contactName).")
                }

                Section("Notiz") {
                    TextField("Wofür? (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if failed {
                    Section { Text("Gerade nicht möglich.").foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Spacer()
                            if sending { ProgressView() } else { Text("Anfordern").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(amountSats == nil || sending)
                    .accessibilityIdentifier("wallet.request.send")
                }
            }
            .navigationTitle("Bitcoin anfordern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { close() } }
            }
            .onAppear { amountFocused = true }
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

    private func send() async {
        guard let sats = amountSats, !sending else { return }
        sending = true
        failed = false
        defer { sending = false }
        if await engine.requestPayment(chatId: chatId, sats: sats, note: note) {
            Haptics.confirm()
            close()
        } else {
            failed = true
            Haptics.error()
        }
    }

    private func close() {
        if let closeSheet { closeSheet() } else { dismiss() }
    }
}
