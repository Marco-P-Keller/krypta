import KryptaBitcoin
import KryptaMessenger
import KryptaWallet
import SwiftUI

/// Eine Bitcoin-Zahlung als Blase im Chat.
///
/// Der Betrag beim Empfänger ist der *geprüfte*: was die Transaktion auf der
/// Blockchain wirklich an seine Adresse zahlt, nicht was die Nachricht sagt.
struct PaymentBubbleContent: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    let payment: ChatPayment
    let messageId: String
    let note: String?
    let mine: Bool

    var body: some View {
        let status = PaymentStatus.of(payment, messageId: messageId, mine: mine, wallet: wallet)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(mine ? AnyShapeStyle(.white) : AnyShapeStyle(Color.orange))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mine ? "Du hast Bitcoin gesendet" : "Bitcoin für dich")
                        .font(.caption.weight(.semibold))
                        .opacity(0.85)
                    Text(verbatim: BitcoinFormat.btc(status.amount))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                NetworkBadge(network: payment.network)
            }
            if let fiat = BitcoinFormat.fiat(status.amount, rate: wallet?.fiatRate), !status.isProblem {
                Text(verbatim: fiat).font(.caption).opacity(0.8)
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(status.text, systemImage: status.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.isProblem && !mine ? AnyShapeStyle(Color.red) : AnyShapeStyle(.foreground))
        }
        .frame(minWidth: 180, alignment: .leading)
    }
}

/// Einzelheiten einer Zahlung aus dem Chat.
struct PaymentDetailView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeSheet) private var closeSheet
    let message: Message

    var body: some View {
        NavigationStack {
            if let payment = message.payment {
                let mine = message.senderId == engine.userId
                let status = PaymentStatus.of(payment, messageId: message.id, mine: mine, wallet: wallet)
                List {
                    Section {
                        VStack(spacing: 6) {
                            Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 44)).foregroundStyle(.orange)
                            Text(verbatim: BitcoinFormat.btc(status.amount)).font(.title.weight(.bold)).monospacedDigit()
                            if let fiat = BitcoinFormat.fiat(status.amount, rate: wallet?.fiatRate) {
                                Text(verbatim: fiat).foregroundStyle(.secondary)
                            }
                            Label(status.text, systemImage: status.symbol)
                                .foregroundStyle(status.isProblem ? .red : .secondary)
                            NetworkBadge(network: payment.network)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    Section {
                        if !mine {
                            LabeledContent("Angekündigt", value: BitcoinFormat.btc(payment.sats))
                        }
                        if mine, let fee = wallet?.transaction(payment.txid)?.fee {
                            LabeledContent("Gebühr", value: BitcoinFormat.sats(fee))
                        }
                        LabeledContent("Netz", value: BitcoinFormat.networkName(payment.network))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mine ? "An Adresse" : "An deine Adresse").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: BitcoinFormat.grouped(payment.address)).font(.callout.monospaced()).textSelection(.enabled)
                        }
                        Button {
                            SecurePasteboard.copy(payment.txid, lifetime: SecurePasteboard.idLifetime)
                            Haptics.confirm()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Transaktion").font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: payment.txid).font(.caption.monospaced()).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                Label("Kopieren", systemImage: "doc.on.doc").font(.caption)
                            }
                        }
                        if let url = payment.network.explorerURL(txid: payment.txid) {
                            Link(destination: url) { Label("Im Block-Explorer ansehen", systemImage: "safari") }
                        }
                    } footer: {
                        Text(mine
                             ? "Die Zahlung läuft über die Bitcoin-Blockchain. Die Nachricht im Chat sagt deinem Kontakt nur, dass und wohin."
                             : "Krypta glaubt der Nachricht nicht, sondern prüft die Transaktion auf der Blockchain: Kennung, Adresse und Betrag. „Bestätigt“ heißt: in einem Block, dessen Beweis Krypta selbst nachgerechnet hat.")
                    }
                }
                .navigationTitle("Bitcoin-Zahlung")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { if let closeSheet { closeSheet() } else { dismiss() } }
                    }
                }
                .refreshable { await wallet?.sync() }
            }
        }
    }
}
