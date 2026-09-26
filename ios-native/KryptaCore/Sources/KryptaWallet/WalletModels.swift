import Foundation
import KryptaBitcoin

/// Eine Zahlung, wie sie verschlüsselt im Chat mitreist (`_pay`).
///
/// Das ist eine *Behauptung* des Absenders. Angezeigt wird beim Empfänger
/// erst, was die Blockchain dazu sagt (`WalletEngine.claimStatus`).
public struct ChatPayment: Codable, Equatable, Hashable, Sendable {
    public let txid: String
    public let vout: UInt32
    public let sats: Int64
    public let address: String
    public let network: BitcoinNetwork

    public init(txid: String, vout: UInt32, sats: Int64, address: String, network: BitcoinNetwork) {
        self.txid = txid.lowercased()
        self.vout = vout
        self.sats = sats
        self.address = address
        self.network = network
    }

    /// Streng: alles, was nicht passt, gilt als nicht vorhanden. Die Adresse
    /// muss für das genannte Netz gültig sein.
    public static func parse(txid: String?, vout: Int?, sats: Int?, address: String?, network: String?) -> ChatPayment? {
        guard let txid, OutPoint.isTxid(txid),
              let vout, (0..<10_000).contains(vout),
              let sats, sats > 0, Int64(sats) <= BitcoinAmount.maxSats,
              let address, (14...90).contains(address.count),
              let network, let net = BitcoinNetwork(rawValue: network),
              let parsed = try? BitcoinAddress(address, network: net) else { return nil }
        return ChatPayment(txid: txid, vout: UInt32(vout), sats: Int64(sats), address: parsed.string, network: net)
    }
}

/// Was die Blockchain zu einer Zahlung im Chat sagt.
public enum PaymentCheck: Codable, Equatable, Sendable {
    /// Noch keine Antwort vom Server.
    case checking
    /// Im Mempool gesehen; der Betrag ist der tatsächlich an mich gezahlte.
    case unconfirmed(received: Int64)
    /// In einem Block. `proven`: Merkle-Beweis und Blockarbeit selbst
    /// geprüft; auf Bitcoin gibt es ohne Beweis kein „bestätigt".
    case confirmed(received: Int64, height: Int, proven: Bool)
    /// Die Transaktion zahlt nicht, was behauptet wird (anderer Betrag,
    /// andere Adresse, gar nicht an mich).
    case mismatch(received: Int64)
    /// Nach mehreren Versuchen nirgends zu finden.
    case notFound
    /// Anderes Netz (z. B. Testnet-Münzen im echten Chat).
    case otherNetwork
}

/// Stand einer eigenen Zahlung.
public enum OutgoingState: String, Codable, Sendable {
    /// Signiert, noch nicht beim Server bestätigt.
    case broadcasting
    /// Der Server hat angenommen.
    case broadcast
    /// Unklar, ob sie raus ist (Netzfehler). Krypta sendet dieselbe
    /// Transaktion erneut, nie eine zweite.
    case uncertain
    /// Abgelehnt; die Münzen sind wieder frei.
    case failed
}

public struct Balance: Equatable, Sendable {
    /// Bestätigt und frei.
    public var confirmed: Int64 = 0
    /// Unterwegs zu mir (unbestätigt, von anderen).
    public var incoming: Int64 = 0
    /// Eigenes Wechselgeld im Mempool: ausgebbar.
    public var ownPending: Int64 = 0

    public var spendable: Int64 { confirmed + ownPending }
    public var total: Int64 { confirmed + incoming + ownPending }

    public init() {}
}

/// Eine Zeile im Verlauf.
public struct WalletTransaction: Codable, Equatable, Identifiable, Sendable {
    public var id: String { txid }
    public let txid: String
    /// Positiv: erhalten, negativ: gesendet (inklusive Gebühr).
    public var net: Int64
    public var fee: Int64?
    public var height: Int?
    public var time: Date
    /// Wer im Chat bezahlt hat oder bezahlt wurde.
    public var contactId: String?
    public var note: String?
    public var outgoing: OutgoingState?

    public var isIncoming: Bool { net > 0 }
    public var isConfirmed: Bool { height != nil }

    public func confirmations(tip: Int?) -> Int {
        guard let height, let tip, tip >= height else { return 0 }
        return tip - height + 1
    }
}

/// Gebührenstufen. Die Sätze kommen vom Server und werden gekappt.
public enum FeeLevel: String, CaseIterable, Codable, Sendable {
    case fast, normal, slow

    /// Ziel in Blöcken (etwa zehn Minuten je Block).
    var target: Int {
        switch self {
        case .fast: 2
        case .normal: 6
        case .slow: 24
        }
    }
}

public struct FeeEstimates: Equatable, Sendable {
    public let fast: Double
    public let normal: Double
    public let slow: Double

    public func rate(_ level: FeeLevel) -> Double {
        switch level {
        case .fast: fast
        case .normal: normal
        case .slow: slow
        }
    }

    /// Aus den Zielen des Servers (`/fee-estimates`), geordnet und in
    /// [1, 1000] sat/vB gehalten.
    public init(targets: [Int: Double]) {
        func rate(_ target: Int) -> Double {
            // Das nächstkleinere Ziel, das der Server kennt (1…25, 144, 504, 1008).
            let valid = targets.filter { $0.value.isFinite && $0.value > 0 }
            let best = valid.filter { $0.key <= target }.max { $0.key < $1.key }?.value
                ?? valid.min { $0.key < $1.key }?.value ?? 1
            return min(TransactionPlanner.maxFeeRate, max(TransactionPlanner.minFeeRate, (best * 10).rounded(.up) / 10))
        }
        let s = rate(FeeLevel.slow.target)
        let n = max(s, rate(FeeLevel.normal.target))
        fast = max(n, rate(FeeLevel.fast.target))
        normal = n
        slow = s
    }

    public init(fast: Double, normal: Double, slow: Double) {
        self.fast = fast
        self.normal = normal
        self.slow = slow
    }
}

public enum WalletFailure: Error, Equatable, Sendable {
    case noWallet
    case offline
    case server(String)
    case insufficientFunds(available: Int64)
    case amountBelowDust(minimum: Int64)
    case feeRateOutOfRange
    case invalidAddress
    case wrongNetwork
    /// Face ID / Code abgebrochen.
    case authenticationCancelled
    case signingFailed
    /// Abgelehnt: die Münzen sind wieder frei.
    case rejected(String)
    /// Unklar, ob gesendet — dieselbe Transaktion geht beim nächsten Abgleich erneut raus.
    case broadcastUncertain(txid: String)
    /// Zwischen Vorbereiten und Senden hat sich etwas geändert.
    case stale
}

/// Ein fertiger Vorschlag zum Bestätigen.
public struct PaymentDraft: Sendable {
    public let plan: PaymentPlan
    public let recipient: BitcoinAddress
    public let contactId: String?
    public let note: String?
    public let feeLevel: FeeLevel?
    let lockTime: UInt32
    let stateVersion: Int

    public var amount: Int64 { plan.amount }
    public var fee: Int64 { plan.fee }
    public var total: Int64 { plan.total }
    /// Gebühr im Verhältnis zum Betrag — über 10 % fragt die App extra nach.
    public var feeShare: Double { Double(plan.fee) / Double(max(1, plan.amount)) }
}

/// Gesendet: das geht in den Chat.
public struct SentPayment: Sendable, Equatable {
    public let txid: String
    public let payment: ChatPayment
    public let fee: Int64
}
