import Foundation
import KryptaBitcoin

/// Zahlungen, die im Chat angekündigt werden.
///
/// Eine Nachricht „ich habe dir 0,01 BTC geschickt" kann jeder schreiben.
/// Angezeigt wird deshalb nur, was die Wallet selbst nachgeprüft hat:
/// 1. Die Adresse ist eine eigene.
/// 2. Die rohe Transaktion hat genau die angegebene Kennung (SHA-256² selbst
///    gerechnet), und ihre Ausgabe `vout` zahlt an diese Adresse — der
///    Betrag, der angezeigt wird, ist der aus der Transaktion.
/// 3. „Bestätigt" nur mit Merkle-Beweis gegen einen Blockkopf, dessen Arbeit
///    stimmt (auf Bitcoin mindestens Schwierigkeit 50 T).
extension WalletEngine {
    /// Höchstens so viele offene Prüfungen je Kontakt: wer mit erfundenen
    /// Zahlungen flutet, blockiert nur seine eigenen, nie die der anderen.
    static let maxOpenClaimsPerContact = 10
    static let maxOpenClaims = 300
    /// Nach so vielen erfolglosen Versuchen gilt eine Zahlung als nicht gefunden.
    static let claimAttempts = 8

    /// Eine Zahlung aus dem Chat zur Prüfung vormerken.
    public func registerClaim(_ payment: ChatPayment, from contactId: String, messageId: String, note: String? = nil) {
        guard state.claims[messageId] == nil else { return }
        let open = state.claims.values.filter { if case .checking = $0.check { return true }; return false }
        guard open.count < Self.maxOpenClaims,
              open.filter({ $0.contactId == contactId }).count < Self.maxOpenClaimsPerContact else { return }
        state.claims[messageId] = .init(payment: payment, contactId: contactId, received: Date(), attempts: 0,
                                        check: payment.network == network ? .checking : .otherNetwork)
        if payment.network == network, let note, !note.isEmpty {
            state.labels[payment.txid] = .init(contactId: contactId, note: String(note.prefix(500)))
        } else if payment.network == network, state.labels[payment.txid] == nil {
            state.labels[payment.txid] = .init(contactId: contactId, note: nil)
        }
        save()
        touch()
        Task { [weak self] in await self?.verifyClaim(messageId) }
    }

    /// Der Absender hat die Gebühr erhöht (RBF): dieselbe Zahlung (Betrag,
    /// Adresse, Netz) steckt jetzt in einer anderen Transaktion. Nur solange
    /// die alte nicht bestätigt ist, und nur auf eine Transaktion, die keine
    /// andere Nachricht schon belegt — sonst ließe sich eine Zahlung zweimal
    /// vorzeigen.
    @discardableResult
    public func replaceClaim(messageId: String, with payment: ChatPayment) -> Bool {
        guard var claim = state.claims[messageId], claim.payment.network == payment.network,
              claim.payment.address == payment.address, claim.payment.sats == payment.sats,
              claim.payment.txid != payment.txid,
              !state.claims.contains(where: { $0.key != messageId && $0.value.payment.txid == payment.txid }) else { return false }
        if case .confirmed = claim.check { return false }
        claim = .init(payment: payment, contactId: claim.contactId, received: Date(), attempts: 0,
                      check: payment.network == network ? .checking : .otherNetwork)
        state.claims[messageId] = claim
        if let label = state.labels[claim.payment.txid] { state.labels[payment.txid] = label }
        save()
        touch()
        Task { [weak self] in await self?.verifyClaim(messageId) }
        return true
    }

    /// Was zu einer Zahlung im Chat feststeht. `nil`: nicht bekannt (z. B.
    /// die eigene; deren Stand steht in `outgoingState`).
    public func claimStatus(messageId: String) -> PaymentCheck? {
        _ = revision
        return state.claims[messageId]?.check
    }

    public func confirmations(height: Int) -> Int {
        guard let tip = state.tip, tip >= height else { return 1 }
        return tip - height + 1
    }

    /// Alles Offene und noch nicht tief Bestätigte erneut prüfen.
    func verifyClaims() async {
        for (id, claim) in state.claims {
            switch claim.check {
            case .checking, .unconfirmed:
                await verifyClaim(id)
            case .confirmed(_, let height, _) where confirmations(height: height) < 6:
                // Bis sechs Bestätigungen: prüfen, ob der Block noch gilt.
                await verifyClaim(id)
            default:
                break
            }
        }
    }

    func verifyClaim(_ messageId: String) async {
        guard let claim = state.claims[messageId], claim.payment.network == network,
              claimTasks.insert(messageId).inserted else { return }
        defer { claimTasks.remove(messageId) }
        let check = await evaluate(claim.payment)
        guard var current = state.claims[messageId] else { return }
        switch check {
        case nil:
            current.attempts += 1
            // Erst nach mehreren Versuchen über einige Zeit aufgeben: eine
            // frische Transaktion braucht einen Moment bis zum Server.
            if current.attempts >= Self.claimAttempts, Date().timeIntervalSince(current.received) > 30 * 60 {
                current.check = .notFound
            }
        case let result?:
            current.check = result
            switch result {
            case .unconfirmed, .confirmed:
                // Die Adresse ist jetzt benutzt: der Kontakt bekommt mit der
                // nächsten Nachricht eine neue.
                let a = claim.payment.address
                if var record = state.addresses[a], record.stats.txCount == 0 {
                    record.stats = AddressStats(txCount: 1, pendingCount: 1, funded: 0, spent: 0)
                    state.addresses[a] = record
                } else if state.addresses[a] == nil, let path = path(of: (try? BitcoinAddress(a, network: network))?.scriptPubKey ?? []) {
                    state.addresses[a] = .init(path: path, stats: AddressStats(txCount: 1, pendingCount: 1, funded: 0, spent: 0))
                }
            default:
                break
            }
        }
        state.claims[messageId] = current
        save()
        touch()
        onChange?()
    }

    /// `nil`: (noch) nicht zu finden oder Server nicht erreichbar.
    func evaluate(_ payment: ChatPayment) async -> PaymentCheck? {
        guard let target = try? BitcoinAddress(payment.address, network: network),
              target.string == payment.address, path(of: target.scriptPubKey) != nil else { return .mismatch(received: 0) }
        guard let raw = try? await chain.rawTransaction(payment.txid) else { return nil }
        guard let tx = try? Transaction.parse(raw), tx.txid == payment.txid else { return .mismatch(received: 0) }
        guard Int(payment.vout) < tx.outputs.count, tx.outputs[Int(payment.vout)].scriptPubKey == target.scriptPubKey else {
            return .mismatch(received: 0)
        }
        let received = tx.outputs[Int(payment.vout)].value
        guard received == payment.sats else { return .mismatch(received: received) }

        guard let status = try? await chain.status(payment.txid) else { return nil }
        guard status.confirmed, let height = status.height, let blockHash = status.blockHash else { return .unconfirmed(received: received) }
        // Bestätigung selbst prüfen: Merkle-Beweis bis in den Kopf, Kopf mit Arbeit.
        guard let proof = try? await chain.merkleProof(payment.txid), proof.height == height,
              let headerBytes = try? await chain.blockHeader(blockHash), let header = try? BlockHeader(headerBytes),
              header.hash == blockHash,
              MerkleProof.verify(txid: payment.txid, siblings: proof.siblings, position: proof.position, header: header, network: network) else {
            return .unconfirmed(received: received)
        }
        return .confirmed(received: received, height: height, proven: true)
    }
}
