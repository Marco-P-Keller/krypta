import Foundation
import KryptaBitcoin

/// Gebühr erhöhen für eine eigene Zahlung, die hängt (Replace-by-Fee).
///
/// Jede Zahlung von Krypta ist als ersetzbar markiert (nSequence
/// 0xFFFFFFFD). Die Ersatztransaktion gibt dieselben Münzen aus, zahlt dem
/// Empfänger genau denselben Betrag an dieselbe Adresse und nimmt die höhere
/// Gebühr aus dem Wechselgeld (TransactionPlanner.replacement). Es wird nie
/// doppelt gezahlt: beide Fassungen geben dieselben Münzen aus, höchstens
/// eine kann gelten.
///
/// Der Ablauf gleicht dem Senden: Face ID, signieren, prüfen, *vor* dem
/// Senden speichern, dann senden. Das Original gilt erst als ersetzt, wenn
/// der Server die neue angenommen hat; bleibt es offen, entscheidet der
/// nächste Abgleich daran, wer die Münzen ausgegeben hat.
extension WalletEngine {
    /// Lässt sich für diese Zahlung die Gebühr erhöhen?
    public func canBump(_ txid: String) -> Bool {
        _ = revision
        guard let out = state.outgoing[txid], out.state == .broadcast || out.state == .uncertain,
              state.history[txid]?.isConfirmed != true, !(out.inputCoins ?? []).isEmpty,
              !state.outgoing.values.contains(where: { $0.replaces == txid && $0.state != .failed }) else { return false }
        return true
    }

    /// Satz und Größe der Zahlung, wie sie jetzt draußen ist.
    public func currentFeeRate(_ txid: String) -> Double? {
        guard let out = state.outgoing[txid], let raw = [UInt8](hex: out.raw), let tx = try? Transaction.parse(raw) else { return nil }
        return Double(out.fee) / Double(max(1, tx.virtualSize))
    }

    public func prepareBump(_ txid: String, feeRate: Double) throws -> BumpDraft {
        guard canBump(txid), let out = state.outgoing[txid], let original = out.inputCoins,
              let raw = [UInt8](hex: out.raw), let tx = try? Transaction.parse(raw),
              let recipient = try? BitcoinAddress(out.recipient, network: network) else { throw WalletFailure.stale }
        // Wechselgeld an dieselbe eigene Adresse wie bisher, sonst an eine frische.
        let changePath: AddressPath
        if let path = out.change?.path {
            changePath = path
        } else {
            var index = state.nextChange
            while isUsed(.change, index) { index += 1 }
            changePath = AddressPath(chain: .change, index: index)
        }
        let changeScript = address(changePath.chain, changePath.index).scriptPubKey
        var rng = SystemRandomNumberGenerator()
        do {
            let plan = try TransactionPlanner.replacement(
                original: original, extra: spendableCoins, recipient: recipient.scriptPubKey, amount: out.amount,
                oldFee: out.fee, oldVSize: tx.virtualSize, feeRate: feeRate,
                changeScript: changeScript, changePath: changePath, using: &rng
            )
            return BumpDraft(originalTxid: txid, plan: plan, recipient: recipient, oldFee: out.fee,
                             oldRate: Double(out.fee) / Double(tx.virtualSize),
                             lockTime: UInt32(clamping: state.tip ?? Int(tx.lockTime)), stateVersion: revision)
        } catch let failure as TransactionPlanner.Failure {
            switch failure {
            case .insufficientFunds(let available): throw WalletFailure.insufficientFunds(available: available)
            case .feeRateOutOfRange: throw WalletFailure.feeRateOutOfRange
            default: throw WalletFailure.insufficientFunds(available: 0)
            }
        }
    }

    /// Signiert und sendet die Ersatztransaktion. Fragt nach Face ID oder Code.
    public func bump(_ draft: BumpDraft, reason: String) async throws -> SentPayment {
        guard canBump(draft.originalTxid), let original = state.outgoing[draft.originalTxid] else { throw WalletFailure.stale }
        // Zusätzliche Münzen müssen noch frei sein; die des Originals sind es für uns.
        func extrasFree() -> Bool {
            let free = Set(spendableCoins.map(\.outPoint)).union(original.inputs)
            return draft.plan.inputs.allSatisfy { free.contains($0.outPoint) }
        }
        guard extrasFree() else { throw WalletFailure.stale }

        let entropy: SecretBytes
        do {
            entropy = try await secrets.entropy(reason: reason)
        } catch let failure as WalletFailure {
            throw failure
        } catch {
            throw WalletFailure.authenticationCancelled
        }
        guard canBump(draft.originalTxid), extrasFree() else { throw WalletFailure.stale }

        let tx: Transaction
        do {
            let seed = try entropy.withBytes { try Mnemonic.seed(entropy: $0) }
            tx = try seed.withBytes { seedBytes in
                try TransactionSigner.sign(draft.plan.unsignedTransaction(lockTime: draft.lockTime), inputs: draft.plan.signerInputs,
                                           seed: seedBytes, network: network)
            }
        } catch {
            throw WalletFailure.signingFailed
        }
        try checkReplacement(tx, draft: draft, original: original)

        let txid = tx.txid
        let changeCoin: Coin? = draft.plan.changeIndex.flatMap { i in
            draft.plan.changePath.map { path in
                Coin(outPoint: try! OutPoint(txid: txid, vout: UInt32(i)), value: tx.outputs[i].value,
                     scriptPubKey: tx.outputs[i].scriptPubKey, path: path, confirmed: false)
            }
        }
        var record = WalletState.Outgoing(
            txid: txid, raw: tx.serialized().hex, state: .broadcasting, created: Date(),
            inputs: draft.plan.inputs.map(\.outPoint), amount: draft.amount, fee: draft.newFee,
            recipient: draft.recipient.string, contactId: original.contactId, note: original.note, change: changeCoin,
            inputCoins: draft.plan.inputs, recipientIndex: draft.plan.recipientIndex
        )
        record.replaces = draft.originalTxid
        state.outgoing[txid] = record
        if let path = draft.plan.changePath { state.nextChange = max(state.nextChange, path.index + 1) }
        save()
        rebuild()

        do {
            let echoed = try await chain.broadcast(tx.serialized())
            guard echoed == txid else { throw ChainError.invalidResponse }
        } catch ChainError.rejected(let reason) where reason.lowercased().contains("already") {
            // Schon da.
        } catch ChainError.rejected(let reason) {
            // Abgelehnt: das Original gilt weiter, nichts ist passiert.
            state.outgoing[txid]?.state = .failed
            save()
            rebuild()
            throw WalletFailure.rejected(reason)
        } catch {
            state.outgoing[txid]?.state = .uncertain
            save()
            rebuild()
            throw WalletFailure.broadcastUncertain(txid: txid)
        }

        // Angenommen: das Original ist abgelöst.
        let old = draft.originalTxid
        state.outgoing[txid]?.state = .broadcast
        state.outgoing[old]?.state = .replaced
        state.history.removeValue(forKey: old)
        if let oldChange = original.change { state.coins.removeAll { $0.outPoint == oldChange.outPoint } }
        let spent = Set(draft.plan.inputs.map(\.outPoint))
        state.coins.removeAll { spent.contains($0.outPoint) }
        if let changeCoin { state.coins.append(changeCoin) }
        state.history[txid] = WalletTransaction(txid: txid, net: -(draft.amount + draft.newFee), fee: draft.newFee, height: nil,
                                                time: original.created, contactId: original.contactId, note: original.note, outgoing: .broadcast)
        if let label = state.labels[old] { state.labels[txid] = label }
        save()
        rebuild()
        onChange?()

        let payment = ChatPayment(txid: txid, vout: UInt32(draft.plan.recipientIndex), sats: draft.amount,
                                  address: draft.recipient.string, network: network)
        return SentPayment(txid: txid, payment: payment, fee: draft.newFee)
    }

    /// Letzte Kontrolle: derselbe Betrag an dieselbe Adresse, Rest an eine
    /// eigene, Gebühr wie angezeigt und höher als vorher, alle Münzen des
    /// Originals wieder dabei.
    func checkReplacement(_ tx: Transaction, draft: BumpDraft, original: WalletState.Outgoing) throws {
        let plan = draft.plan
        guard tx.outputs.count == plan.outputs.count,
              tx.outputs[plan.recipientIndex] == TxOutput(value: original.amount, scriptPubKey: draft.recipient.scriptPubKey),
              Set(tx.inputs.map(\.outPoint)).isSuperset(of: original.inputs) else {
            throw WalletFailure.signingFailed
        }
        if let i = plan.changeIndex {
            guard let path = plan.changePath, tx.outputs[i].scriptPubKey == address(path.chain, path.index).scriptPubKey else {
                throw WalletFailure.signingFailed
            }
        }
        let inSum = plan.inputs.reduce(0) { $0 + $1.value }
        let outSum = tx.outputs.reduce(0) { $0 + $1.value }
        guard inSum - outSum == draft.newFee, draft.newFee > original.fee,
              Double(draft.newFee) <= Double(tx.virtualSize) * TransactionPlanner.maxFeeRate else {
            throw WalletFailure.signingFailed
        }
    }
}
