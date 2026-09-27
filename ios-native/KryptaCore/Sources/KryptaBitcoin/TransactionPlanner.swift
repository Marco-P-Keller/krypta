import Foundation

/// Eine eigene, ausgebbare Ausgabe (UTXO).
public struct Coin: Hashable, Codable, Sendable {
    public let outPoint: OutPoint
    public let value: Int64
    public let scriptPubKey: [UInt8]
    public let path: AddressPath
    public let confirmed: Bool

    public init(outPoint: OutPoint, value: Int64, scriptPubKey: [UInt8], path: AddressPath, confirmed: Bool) {
        self.outPoint = outPoint
        self.value = value
        self.scriptPubKey = scriptPubKey
        self.path = path
        self.confirmed = confirmed
    }

    var signerInput: TransactionSigner.Input {
        .init(outPoint: outPoint, value: value, scriptPubKey: scriptPubKey, path: path)
    }
}

/// Was gesendet werden soll, fertig gerechnet, aber noch nicht signiert.
public struct PaymentPlan: Sendable {
    public let inputs: [Coin]
    /// In der endgültigen (zufälligen) Reihenfolge.
    public let outputs: [TxOutput]
    public let recipientIndex: Int
    public let changeIndex: Int?
    public let changePath: AddressPath?
    public let amount: Int64
    public let fee: Int64
    /// Obergrenze der Größe (Signaturen im ungünstigsten Fall 72 Bytes).
    public let estimatedVSize: Int
    public let feeRate: Double

    public var change: Int64 { changeIndex.map { outputs[$0].value } ?? 0 }
    public var total: Int64 { amount + fee }

    /// Unsigniert, mit RBF-Kennzeichen und Sperrzeit gegen Fee Sniping.
    public func unsignedTransaction(lockTime: UInt32) -> Transaction {
        Transaction(
            version: 2,
            inputs: inputs.map { TxInput(outPoint: $0.outPoint, sequence: 0xFFFF_FFFD) },
            outputs: outputs,
            lockTime: lockTime
        )
    }

    public var signerInputs: [TransactionSigner.Input] { inputs.map(\.signerInput) }
}

/// Münzauswahl und Gebühr.
///
/// Absichtlich einfach und nachvollziehbar: zuerst eine einzelne Münze, die
/// ohne Wechselgeld passt, sonst die größten zuerst. Die Gebühr rechnet mit
/// der größtmöglichen Signatur, der tatsächliche Satz liegt also nie unter
/// dem gewählten. Jede Rechnung ist ganzzahlig in Satoshi.
public enum TransactionPlanner {
    public static let minFeeRate = 1.0
    /// Darüber ist ein Satz sicher ein Fehler (oder ein lügender Server).
    public static let maxFeeRate = 1000.0
    public static let maxInputs = 500

    public enum Amount: Equatable, Sendable {
        case exact(Int64)
        /// Alles, abzüglich Gebühr, ohne Wechselgeld.
        case all
    }

    public enum Failure: Error, Equatable, Sendable {
        case feeRateOutOfRange
        case amountBelowDust(minimum: Int64)
        case insufficientFunds(available: Int64)
        case nothingToSpend
        case tooManyInputs
    }

    static let inputWeight = 4 * (32 + 4 + 1 + 4) + (1 + 1 + 72 + 1 + 33)

    /// Gewicht einer Transaktion mit `inputs` P2WPKH-Eingängen und diesen Ausgaben.
    public static func weight(inputs: Int, outputScripts: [[UInt8]]) -> Int {
        var base = 4 + [UInt8].varIntSize(inputs) + inputs * 41 + [UInt8].varIntSize(outputScripts.count) + 4
        for s in outputScripts { base += 8 + [UInt8].varIntSize(s.count) + s.count }
        let witness = 2 + inputs * (1 + 1 + 72 + 1 + 33)
        return base * 4 + witness
    }

    public static func vsize(inputs: Int, outputScripts: [[UInt8]]) -> Int {
        (weight(inputs: inputs, outputScripts: outputScripts) + 3) / 4
    }

    static func fee(vsize: Int, rate: Double) -> Int64 {
        Int64((Double(vsize) * rate).rounded(.up))
    }

    public static func plan<R: RandomNumberGenerator>(
        coins: [Coin],
        recipient: [UInt8],
        amount: Amount,
        feeRate: Double,
        changeScript: [UInt8],
        changePath: AddressPath,
        using rng: inout R
    ) throws -> PaymentPlan {
        guard feeRate.isFinite, feeRate >= minFeeRate, feeRate <= maxFeeRate else { throw Failure.feeRateOutOfRange }
        let usable = coins.filter { $0.value > 0 }
        guard !usable.isEmpty else { throw Failure.nothingToSpend }
        let recipientDust = BitcoinAddress.dustLimit(scriptPubKey: recipient)
        let changeDust = BitcoinAddress.dustLimit(scriptPubKey: changeScript)

        func finish(_ selected: [Coin], send: Int64, change: Int64?) -> PaymentPlan {
            var outputs = [TxOutput(value: send, scriptPubKey: recipient)]
            if let change { outputs.append(TxOutput(value: change, scriptPubKey: changeScript)) }
            // Zufällige Reihenfolge: sonst verriete die Position das Wechselgeld.
            let swapped = outputs.count == 2 && Bool.random(using: &rng)
            if swapped { outputs.swapAt(0, 1) }
            let recipientIndex = swapped ? 1 : 0
            let changeIndex = change == nil ? nil : 1 - recipientIndex
            let total = selected.reduce(0) { $0 + $1.value }
            let scripts = outputs.map(\.scriptPubKey)
            return PaymentPlan(
                inputs: selected, outputs: outputs, recipientIndex: recipientIndex, changeIndex: changeIndex,
                changePath: change == nil ? nil : changePath, amount: send,
                fee: total - send - (change ?? 0),
                estimatedVSize: vsize(inputs: selected.count, outputScripts: scripts), feeRate: feeRate
            )
        }

        switch amount {
        case .all:
            guard usable.count <= maxInputs else { throw Failure.tooManyInputs }
            let total = usable.reduce(0) { $0 + $1.value }
            let f = fee(vsize: vsize(inputs: usable.count, outputScripts: [recipient]), rate: feeRate)
            let send = total - f
            guard send >= recipientDust else { throw Failure.insufficientFunds(available: max(0, send)) }
            return finish(usable, send: send, change: nil)

        case .exact(let send):
            guard send >= recipientDust else { throw Failure.amountBelowDust(minimum: recipientDust) }
            guard send <= BitcoinAmount.maxSats else { throw Failure.insufficientFunds(available: 0) }
            // Bestätigte zuerst, dann die größten.
            let sorted = usable.sorted { ($0.confirmed ? 1 : 0, $0.value) > ($1.confirmed ? 1 : 0, $1.value) }
            let feeWithout = { (n: Int) in fee(vsize: vsize(inputs: n, outputScripts: [recipient]), rate: feeRate) }
            let feeWith = { (n: Int) in fee(vsize: vsize(inputs: n, outputScripts: [recipient, changeScript]), rate: feeRate) }
            // Was Wechselgeld kostet: die Ausgabe jetzt und ihr Ausgeben später.
            let changeCost = max(changeDust, feeWith(1) - feeWithout(1) + fee(vsize: inputWeight / 4, rate: feeRate))

            // 1. Eine Münze, die ohne Wechselgeld fast genau passt.
            let exact = sorted.filter { coin in
                let excess = coin.value - send - feeWithout(1)
                return excess >= 0 && excess < changeCost
            }.min { $0.value < $1.value }
            if let coin = exact { return finish([coin], send: send, change: nil) }

            // 2. Die größten zuerst, bis es reicht.
            var selected = [Coin]()
            var total: Int64 = 0
            for coin in sorted {
                // Münzen, deren Ausgeben mehr kostet, als sie bringen, bleiben liegen.
                guard coin.value > fee(vsize: inputWeight / 4, rate: feeRate) else { continue }
                selected.append(coin)
                total += coin.value
                guard selected.count <= maxInputs else { throw Failure.tooManyInputs }
                let n = selected.count
                if total >= send + feeWith(n) {
                    let change = total - send - feeWith(n)
                    if change >= changeDust { return finish(selected, send: send, change: change) }
                    // Zu wenig für eine eigene Ausgabe: geht in die Gebühr.
                    return finish(selected, send: send, change: nil)
                }
                if total >= send + feeWithout(n) {
                    // Reicht nur ohne Wechselgeld; der Rest (weniger als eine
                    // Wechselgeld-Ausgabe kosten würde) wird Gebühr.
                    return finish(selected, send: send, change: nil)
                }
            }
            let all = sorted.filter { $0.value > fee(vsize: inputWeight / 4, rate: feeRate) }
            let available = all.reduce(0) { $0 + $1.value } - feeWithout(max(1, all.count))
            throw Failure.insufficientFunds(available: max(0, available))
        }
    }

    /// Satz, um den eine Ersatztransaktion mindestens mehr zahlen muss
    /// (incrementalRelayFee von Bitcoin Core, BIP125 Regel 4).
    public static let incrementalRelayRate = 1.0

    /// Dieselbe Zahlung mit höherer Gebühr (Replace-by-Fee, BIP125).
    ///
    /// Gibt dieselben Münzen aus wie das Original, zahlt dem Empfänger genau
    /// denselben Betrag und nimmt die zusätzliche Gebühr aus dem
    /// Wechselgeld. Reicht es nicht, kommen bestätigte Münzen dazu — neue
    /// unbestätigte Eingänge erlaubt BIP125 nicht. Die neue Gebühr ist
    /// mindestens die alte plus 1 sat/vB auf die neue Größe, und der Satz
    /// liegt über dem alten.
    public static func replacement<R: RandomNumberGenerator>(
        original: [Coin],
        extra: [Coin],
        recipient: [UInt8],
        amount: Int64,
        oldFee: Int64,
        oldVSize: Int,
        feeRate: Double,
        changeScript: [UInt8],
        changePath: AddressPath,
        using rng: inout R
    ) throws -> PaymentPlan {
        guard feeRate.isFinite, feeRate >= minFeeRate, feeRate <= maxFeeRate, oldVSize > 0,
              feeRate > Double(oldFee) / Double(oldVSize) else { throw Failure.feeRateOutOfRange }
        guard !original.isEmpty else { throw Failure.nothingToSpend }
        let changeDust = BitcoinAddress.dustLimit(scriptPubKey: changeScript)
        var inputs = original
        var pool = extra.filter { $0.confirmed && $0.value > 0 }.sorted { $0.value > $1.value }

        func required(_ vsize: Int) -> Int64 {
            max(fee(vsize: vsize, rate: feeRate), oldFee + fee(vsize: vsize, rate: incrementalRelayRate))
        }

        while true {
            let total = inputs.reduce(0) { $0 + $1.value }
            let vWith = vsize(inputs: inputs.count, outputScripts: [recipient, changeScript])
            let change = total - amount - required(vWith)
            if change >= changeDust {
                return assemble(inputs, recipient: recipient, send: amount, change: change, changeScript: changeScript,
                                changePath: changePath, feeRate: feeRate, using: &rng)
            }
            let vWithout = vsize(inputs: inputs.count, outputScripts: [recipient])
            if total - amount >= required(vWithout) {
                // Ohne Wechselgeld: der Rest (weniger als eine Ausgabe wert) wird Gebühr.
                return assemble(inputs, recipient: recipient, send: amount, change: nil, changeScript: changeScript,
                                changePath: changePath, feeRate: feeRate, using: &rng)
            }
            guard !pool.isEmpty, inputs.count < maxInputs else {
                throw Failure.insufficientFunds(available: max(0, total - required(vWithout)))
            }
            inputs.append(pool.removeFirst())
        }
    }

    static func assemble<R: RandomNumberGenerator>(_ selected: [Coin], recipient: [UInt8], send: Int64, change: Int64?, changeScript: [UInt8],
                                                   changePath: AddressPath, feeRate: Double, using rng: inout R) -> PaymentPlan {
        var outputs = [TxOutput(value: send, scriptPubKey: recipient)]
        if let change { outputs.append(TxOutput(value: change, scriptPubKey: changeScript)) }
        let swapped = outputs.count == 2 && Bool.random(using: &rng)
        if swapped { outputs.swapAt(0, 1) }
        let recipientIndex = swapped ? 1 : 0
        let total = selected.reduce(0) { $0 + $1.value }
        return PaymentPlan(
            inputs: selected, outputs: outputs, recipientIndex: recipientIndex, changeIndex: change == nil ? nil : 1 - recipientIndex,
            changePath: change == nil ? nil : changePath, amount: send, fee: total - send - (change ?? 0),
            estimatedVSize: vsize(inputs: selected.count, outputScripts: outputs.map(\.scriptPubKey)), feeRate: feeRate
        )
    }
}
