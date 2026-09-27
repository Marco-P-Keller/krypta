import KryptaBitcoin
import KryptaMessenger
import KryptaWallet
import SwiftUI

/// Beträge und Zustände für die Anzeige.
enum BitcoinFormat {
    static var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    /// „0,0021 BTC", ohne überflüssige Nullen; mit `sign` auch „+"/„−".
    static func btc(_ sats: Int64, sign: Bool = false) -> String {
        let plain = BitcoinAmount.plainBTC(sats.magnitude > UInt64(Int64.max) ? 0 : Int64(sats.magnitude))
            .replacingOccurrences(of: ".", with: decimalSeparator)
        let prefix = sats < 0 ? "−" : (sign && sats > 0 ? "+" : "")
        return prefix + plain + " BTC"
    }

    /// Guthaben: immer acht Stellen, in Gruppen („0,00 210 000").
    static func balance(_ sats: Int64) -> String {
        BitcoinAmount.formatBTC(sats, decimalSeparator: decimalSeparator)
    }

    static func sats(_ sats: Int64) -> String {
        sats.formatted(.number) + " sat"
    }

    /// „≈ 181,23 CHF", nur wenn ein Kurs da ist.
    static func fiat(_ sats: Int64, rate: (currency: String, price: Double)?) -> String? {
        guard let rate, rate.price > 0 else { return nil }
        let value = Double(sats) / Double(BitcoinAmount.satsPerBTC) * rate.price
        return "≈ " + value.formatted(.currency(code: rate.currency))
    }

    static func feeRate(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...1))) + " sat/vB"
    }

    /// Adresse in Vierergruppen, damit man sie vergleichen kann.
    static func grouped(_ address: String) -> String {
        stride(from: 0, to: address.count, by: 4).map { i -> String in
            let start = address.index(address.startIndex, offsetBy: i)
            let end = address.index(start, offsetBy: min(4, address.count - i))
            return String(address[start..<end])
        }.joined(separator: " ")
    }

    static func networkName(_ network: BitcoinNetwork) -> String {
        switch network {
        case .mainnet: "Bitcoin"
        case .testnet4: "Testnet4"
        case .signet: "Signet"
        case .regtest: "Regtest"
        }
    }

    /// Was bei einem Fehler zu sagen ist. `nil`: nichts (abgebrochen).
    static func message(_ failure: WalletFailure) -> String? {
        switch failure {
        case .authenticationCancelled:
            return nil
        case .noWallet:
            return String(localized: "Keine Wallet gefunden.")
        case .offline:
            return String(localized: "Keine Verbindung zum Bitcoin-Server.")
        case .server:
            return String(localized: "Der Bitcoin-Server antwortet gerade nicht richtig. Versuch es gleich noch einmal.")
        case .insufficientFunds(let available):
            return String(localized: "Nicht genug Guthaben. Verfügbar sind \(btc(available)) (nach Gebühr).")
        case .amountBelowDust(let minimum):
            return String(localized: "Der Betrag ist zu klein. Mindestens \(sats(minimum)).")
        case .feeRateOutOfRange:
            return String(localized: "Die Gebühr des Servers ist unplausibel. Versuch es später.")
        case .invalidAddress:
            return String(localized: "Das ist keine gültige Bitcoin-Adresse.")
        case .wrongNetwork:
            return String(localized: "Diese Adresse gehört zu einem anderen Bitcoin-Netz.")
        case .signingFailed:
            return String(localized: "Signieren fehlgeschlagen. Es wurde nichts gesendet.")
        case .rejected:
            return String(localized: "Der Server hat die Zahlung abgelehnt. Es wurde nichts gesendet.")
        case .broadcastUncertain:
            return String(localized: "Die Verbindung ist abgebrochen. Ob die Zahlung raus ist, prüft Krypta beim nächsten Abgleich und sendet dann genau dieselbe Zahlung noch einmal, nie eine zweite.")
        case .stale:
            return String(localized: "Dein Guthaben hat sich gerade geändert. Prüfe die Zahlung bitte noch einmal.")
        }
    }
}

/// Ein Hinweis, dass es kein echtes Geld ist.
struct NetworkBadge: View {
    let network: BitcoinNetwork

    var body: some View {
        if network.isTest {
            Text(verbatim: BitcoinFormat.networkName(network).uppercased())
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.orange.opacity(0.18), in: Capsule())
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("Testnetz, kein echtes Geld"))
        }
    }
}

/// Wie eine Zahlung im Chat steht, in Worten und als Symbol.
struct PaymentStatus: Equatable {
    let text: String
    let symbol: String
    let isProblem: Bool
    /// Der Betrag, der tatsächlich zählt (beim Empfänger der geprüfte).
    let amount: Int64

    @MainActor
    static func of(_ payment: ChatPayment, messageId: String, mine: Bool, wallet: WalletEngine?) -> PaymentStatus {
        guard let wallet else {
            return .init(text: String(localized: "Bitcoin-Zahlung"), symbol: "bitcoinsign.circle", isProblem: false, amount: payment.sats)
        }
        if mine {
            switch wallet.outgoingState(payment.txid) {
            case nil:
                return .init(text: String(localized: "Gesendet"), symbol: "paperplane", isProblem: false, amount: payment.sats)
            case (.broadcasting, _)?:
                return .init(text: String(localized: "Wird gesendet …"), symbol: "arrow.up.circle", isProblem: false, amount: payment.sats)
            case (.uncertain, _)?:
                return .init(text: String(localized: "Unklar, Krypta prüft"), symbol: "questionmark.circle", isProblem: true, amount: payment.sats)
            case (.failed, _)?:
                return .init(text: String(localized: "Nicht gesendet"), symbol: "xmark.octagon", isProblem: true, amount: payment.sats)
            case (.replaced, _)?:
                return .init(text: String(localized: "Ersetzt (höhere Gebühr)"), symbol: "arrow.triangle.2.circlepath", isProblem: false, amount: payment.sats)
            case (.broadcast, let height?)?:
                return confirmed(wallet.confirmations(height: height), amount: payment.sats)
            case (.broadcast, nil)?:
                return .init(text: String(localized: "Unbestätigt"), symbol: "hourglass", isProblem: false, amount: payment.sats)
            }
        }
        guard payment.network == wallet.network else {
            return .init(text: String(localized: "Anderes Bitcoin-Netz"), symbol: "exclamationmark.triangle", isProblem: true, amount: 0)
        }
        switch wallet.claimStatus(messageId: messageId) {
        case nil, .checking?:
            return .init(text: String(localized: "Wird geprüft …"), symbol: "magnifyingglass", isProblem: false, amount: payment.sats)
        case .unconfirmed(let received)?:
            return .init(text: String(localized: "Unbestätigt"), symbol: "hourglass", isProblem: false, amount: received)
        case .confirmed(let received, let height, _)?:
            return confirmed(wallet.confirmations(height: height), amount: received)
        case .mismatch(let received)?:
            return .init(text: received > 0
                         ? String(localized: "Stimmt nicht: angekommen sind \(BitcoinFormat.btc(received))")
                         : String(localized: "Stimmt nicht: nicht an dich"),
                         symbol: "exclamationmark.triangle.fill", isProblem: true, amount: received)
        case .notFound?:
            return .init(text: String(localized: "Nicht auf der Blockchain gefunden"), symbol: "exclamationmark.triangle.fill", isProblem: true, amount: 0)
        case .otherNetwork?:
            return .init(text: String(localized: "Anderes Bitcoin-Netz"), symbol: "exclamationmark.triangle", isProblem: true, amount: 0)
        }
    }

    private static func confirmed(_ n: Int, amount: Int64) -> PaymentStatus {
        n >= 6
            ? .init(text: String(localized: "Bestätigt"), symbol: "checkmark.seal.fill", isProblem: false, amount: amount)
            : .init(text: String(localized: "Bestätigt (\(n) von 6)"), symbol: "checkmark.seal", isProblem: false, amount: amount)
    }
}

/// Ein Blatt der Wallet, aus Bildschirmfotos und Aufnahmen herausgehalten
/// wie die Chats. Blätter liegen außerhalb der geschützten Fläche darunter,
/// deshalb bekommt jedes seine eigene; die Umgebung reicht SwiftUI über die
/// Grenze nicht weiter, sie wird hier ausdrücklich übergeben.
///
/// `always`: unabhängig von der Einstellung (die zwölf Wörter).
struct ShieldedSheet<Content: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(MessengerEngine.self) private var engine
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(\.dismiss) private var dismiss
    var always = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScreenshotShield(isEnabled: always || app.screenshotShield) {
            content()
                .environment(engine)
                .environment(app)
                .environment(wallet)
                // `dismiss` gilt drinnen nicht für dieses Blatt; so schon.
                .environment(\.closeSheet, CloseSheetAction { dismiss() })
        }
        .ignoresSafeArea()
    }
}

/// Schließt das Blatt, in dem eine Ansicht liegt, auch durch den
/// Screenshot-Schutz hindurch (siehe `ShieldedSheet`).
struct CloseSheetAction {
    let run: @MainActor () -> Void

    @MainActor
    func callAsFunction() { run() }
}

private struct CloseSheetKey: EnvironmentKey {
    static var defaultValue: CloseSheetAction? { nil }
}

extension EnvironmentValues {
    var closeSheet: CloseSheetAction? {
        get { self[CloseSheetKey.self] }
        set { self[CloseSheetKey.self] = newValue }
    }
}
