import KryptaBitcoin
import KryptaMessenger
import KryptaWallet
import SwiftUI

/// Gebühr erhöhen für eine eigene Zahlung, die hängt (Replace-by-Fee).
///
/// Zeigt den bisherigen Satz, schlägt höhere vor und rechnet vorher aus,
/// was die Erhöhung kostet. Der Empfänger bekommt denselben Betrag; die
/// höhere Gebühr geht vom eigenen Wechselgeld ab.
struct BumpFeeView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeSheet) private var closeSheet
    let txid: String

    @State private var rate: Double?
    @State private var draft: BumpDraft?
    @State private var problem: String?
    @State private var working = false
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                if let wallet, let current = wallet.currentFeeRate(txid) {
                    Section {
                        LabeledContent("Bisher") { Text(verbatim: Self.rateText(current)).monospacedDigit() }
                        Picker(selection: Binding(get: { rate ?? choices(current).first ?? current }, set: { rate = $0; recalc() })) {
                            ForEach(choices(current), id: \.self) { r in
                                Text(verbatim: Self.rateText(r)).tag(r)
                            }
                        } label: {
                            Text("Neu")
                        }
                        if let draft {
                            LabeledContent("Gebühr vorher") { Text(verbatim: BitcoinFormat.sats(draft.oldFee)).monospacedDigit() }
                            LabeledContent("Gebühr neu") { Text(verbatim: BitcoinFormat.sats(draft.newFee)).monospacedDigit() }
                            LabeledContent("Kostet zusätzlich") { Text(verbatim: BitcoinFormat.sats(draft.extraCost)).monospacedDigit().bold() }
                        }
                    } footer: {
                        Text("Der Empfänger bekommt genau denselben Betrag. Die neue Transaktion ersetzt die alte; beide geben dieselben Münzen aus, es kann also nur eine gelten. Im Chat bekommt dein Kontakt die neue Kennung verschlüsselt nachgereicht.")
                    }
                    if let problem {
                        Section { Text(problem).foregroundStyle(.red) }
                    }
                    Section {
                        Button {
                            send()
                        } label: {
                            HStack {
                                Spacer()
                                if working { ProgressView() } else { Text("Gebühr erhöhen").bold() }
                                Spacer()
                            }
                        }
                        .disabled(draft == nil || working)
                    }
                } else {
                    Text("Für diese Zahlung lässt sich die Gebühr nicht mehr erhöhen.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Gebühr erhöhen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { close() } }
            }
            .onAppear(perform: recalc)
            .sensoryFeedback(.success, trigger: done)
        }
    }

    /// Vorschläge über dem bisherigen Satz: „schnell" vom Server und ein paar Stufen.
    private func choices(_ current: Double) -> [Double] {
        var list = [current * 1.5, current * 2, current * 4].map { max($0, current + 1) }
        if let fast = wallet?.feeEstimates?.fast, fast > current { list.append(fast) }
        let rounded = list.map { ($0 * 10).rounded(.up) / 10 }.filter { $0 > current && $0 <= TransactionPlanner.maxFeeRate }
        return Array(Set(rounded)).sorted()
    }

    private static func rateText(_ r: Double) -> String {
        String(format: "%.1f sat/vB", r)
    }

    private func recalc() {
        guard let wallet, let current = wallet.currentFeeRate(txid) else { return }
        let chosen = rate ?? choices(current).first ?? current + 1
        rate = chosen
        do {
            draft = try wallet.prepareBump(txid, feeRate: chosen)
            problem = nil
        } catch WalletFailure.insufficientFunds {
            draft = nil
            problem = String(localized: "Dafür reicht das freie Guthaben nicht. Bestätigte Münzen kämen dazu, aber es gibt keine.")
        } catch {
            draft = nil
            problem = String(localized: "Für diese Zahlung lässt sich die Gebühr nicht mehr erhöhen.")
        }
    }

    private func send() {
        guard let draft else { return }
        working = true
        Task {
            defer { working = false }
            do {
                _ = try await engine.bumpFee(draft, reason: String(localized: "Gebühr erhöhen"))
                done = true
                close()
            } catch WalletFailure.authenticationCancelled {
                // Abgebrochen: nichts passiert.
            } catch WalletFailure.broadcastUncertain {
                problem = String(localized: "Die Verbindung brach ab. Krypta prüft beim nächsten Abgleich, welche der beiden Transaktionen gilt; doppelt gezahlt wird nie.")
            } catch WalletFailure.rejected {
                problem = String(localized: "Der Server hat die Erhöhung abgelehnt. Die bisherige Zahlung gilt weiter.")
                recalc()
            } catch {
                problem = String(localized: "Das hat nicht geklappt. Die bisherige Zahlung gilt weiter.")
                recalc()
            }
        }
    }

    private func close() {
        if let closeSheet { closeSheet() } else { dismiss() }
    }
}
