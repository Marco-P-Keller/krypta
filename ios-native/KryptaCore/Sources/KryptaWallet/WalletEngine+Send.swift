import Foundation
import KryptaBitcoin

extension WalletEngine {
    /// Rechnet eine Zahlung durch, ohne etwas zu signieren.
    public func prepare(to recipient: BitcoinAddress, amount: TransactionPlanner.Amount, feeLevel: FeeLevel,
                        contactId: String? = nil, note: String? = nil) throws -> PaymentDraft {
        guard let fees = feeEstimates else { throw WalletFailure.offline }
        return try prepare(to: recipient, amount: amount, feeRate: fees.rate(feeLevel), feeLevel: feeLevel, contactId: contactId, note: note)
    }

    public func prepare(to recipient: BitcoinAddress, amount: TransactionPlanner.Amount, feeRate: Double, feeLevel: FeeLevel? = nil,
                        contactId: String? = nil, note: String? = nil) throws -> PaymentDraft {
        guard recipient.network.hrp == network.hrp else { throw WalletFailure.wrongNetwork }
        // Wechselgeld an eine frische Adresse, nie an eine schon benutzte.
        var changeIndex = state.nextChange
        while isUsed(.change, changeIndex) { changeIndex += 1 }
        let change = address(.change, changeIndex)
        var rng = SystemRandomNumberGenerator()
        do {
            let plan = try TransactionPlanner.plan(
                coins: spendableCoins, recipient: recipient.scriptPubKey, amount: amount, feeRate: feeRate,
                changeScript: change.scriptPubKey, changePath: AddressPath(chain: .change, index: changeIndex), using: &rng
            )
            return PaymentDraft(plan: plan, recipient: recipient, contactId: contactId,
                                note: note.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }, feeLevel: feeLevel,
                                lockTime: UInt32(clamping: state.tip ?? 0), stateVersion: revision)
        } catch let failure as TransactionPlanner.Failure {
            switch failure {
            case .insufficientFunds(let available): throw WalletFailure.insufficientFunds(available: available)
            case .nothingToSpend: throw WalletFailure.insufficientFunds(available: 0)
            case .amountBelowDust(let minimum): throw WalletFailure.amountBelowDust(minimum: minimum)
            case .feeRateOutOfRange: throw WalletFailure.feeRateOutOfRange
            case .tooManyInputs: throw WalletFailure.insufficientFunds(available: 0)
            }
        }
    }

    /// Signiert und sendet. Fragt nach Face ID oder Code.
    ///
    /// Reihenfolge, damit nie doppelt gezahlt wird:
    /// 1. prüfen, dass die Münzen noch frei sind,
    /// 2. signieren (Schlüssel nur für diesen Moment im Speicher),
    /// 3. die signierte Transaktion *vor* dem Senden speichern und ihre
    ///    Münzen sperren,
    /// 4. senden. Lehnt der Server ab, werden die Münzen frei. Bleibt offen,
    ///    ob er sie bekam, bleiben sie gesperrt, und der nächste Abgleich
    ///    sendet genau diese Transaktion erneut.
    public func send(_ draft: PaymentDraft, reason: String) async throws -> SentPayment {
        let free = Set(spendableCoins.map(\.outPoint))
        guard draft.plan.inputs.allSatisfy({ free.contains($0.outPoint) }) else { throw WalletFailure.stale }

        let entropy: SecretBytes
        do {
            entropy = try await secrets.entropy(reason: reason)
        } catch let failure as WalletFailure {
            throw failure
        } catch {
            throw WalletFailure.authenticationCancelled
        }
        // Während Face ID offen war, kann ein Abgleich Münzen verändert haben.
        let stillFree = Set(spendableCoins.map(\.outPoint))
        guard draft.plan.inputs.allSatisfy({ stillFree.contains($0.outPoint) }) else { throw WalletFailure.stale }

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
        try checkOutputs(tx, draft: draft)

        let txid = tx.txid
        let changeCoin: Coin? = draft.plan.changeIndex.flatMap { i in
            draft.plan.changePath.map { path in
                Coin(outPoint: try! OutPoint(txid: txid, vout: UInt32(i)), value: tx.outputs[i].value,
                     scriptPubKey: tx.outputs[i].scriptPubKey, path: path, confirmed: false)
            }
        }
        state.outgoing[txid] = .init(
            txid: txid, raw: tx.serialized().hex, state: .broadcasting, created: Date(),
            inputs: draft.plan.inputs.map(\.outPoint), amount: draft.amount, fee: draft.fee,
            recipient: draft.recipient.string, contactId: draft.contactId, note: draft.note, change: changeCoin
        )
        if let path = draft.plan.changePath { state.nextChange = max(state.nextChange, path.index + 1) }
        save()
        rebuild()

        do {
            let echoed = try await chain.broadcast(tx.serialized())
            guard echoed == txid else { throw ChainError.invalidResponse }
        } catch ChainError.rejected(let reason) where reason.lowercased().contains("already") {
            // Schon da (zweiter Versuch derselben Transaktion): gut.
        } catch ChainError.rejected(let reason) {
            // Sicher nicht angenommen, und nur dieser Server hatte sie.
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

        state.outgoing[txid]?.state = .broadcast
        let spent = Set(draft.plan.inputs.map(\.outPoint))
        state.coins.removeAll { spent.contains($0.outPoint) }
        if let changeCoin { state.coins.append(changeCoin) }
        state.history[txid] = WalletTransaction(txid: txid, net: -(draft.amount + draft.fee), fee: draft.fee, height: nil,
                                                time: Date(), contactId: draft.contactId, note: draft.note, outgoing: .broadcast)
        if let contactId = draft.contactId { state.labels[txid] = .init(contactId: contactId, note: draft.note) }
        save()
        rebuild()
        onChange?()

        let payment = ChatPayment(txid: txid, vout: UInt32(draft.plan.recipientIndex), sats: draft.amount,
                                  address: draft.recipient.string, network: network)
        return SentPayment(txid: txid, payment: payment, fee: draft.fee)
    }

    /// Letzte Kontrolle der signierten Transaktion gegen den Entwurf: an den
    /// Empfänger genau der Betrag, der Rest an eine eigene Adresse, die
    /// Gebühr wie angezeigt.
    func checkOutputs(_ tx: Transaction, draft: PaymentDraft) throws {
        let plan = draft.plan
        guard tx.outputs.count == plan.outputs.count,
              tx.outputs[plan.recipientIndex] == TxOutput(value: draft.amount, scriptPubKey: draft.recipient.scriptPubKey) else {
            throw WalletFailure.signingFailed
        }
        if let i = plan.changeIndex {
            guard let path = plan.changePath, tx.outputs[i].scriptPubKey == address(path.chain, path.index).scriptPubKey else {
                throw WalletFailure.signingFailed
            }
        }
        let inSum = plan.inputs.reduce(0) { $0 + $1.value }
        let outSum = tx.outputs.reduce(0) { $0 + $1.value }
        guard inSum - outSum == draft.fee, draft.fee >= 0, Double(draft.fee) <= Double(tx.virtualSize) * TransactionPlanner.maxFeeRate else {
            throw WalletFailure.signingFailed
        }
    }

    /// Was aus einer eigenen Zahlung geworden ist.
    public func outgoingState(_ txid: String) -> (state: OutgoingState, height: Int?)? {
        _ = revision
        if let out = state.outgoing[txid] { return (out.state, state.history[txid]?.height) }
        if let tx = state.history[txid], tx.net < 0 { return (.broadcast, tx.height) }
        return nil
    }

    /// Die zwölf Wörter zum Aufschreiben. Fragt nach Face ID oder Code.
    public func recoveryWords(reason: String) async throws -> [String] {
        let entropy = try await secrets.entropy(reason: reason)
        return try entropy.withBytes { try Mnemonic.words(entropy: $0) }
    }
}
