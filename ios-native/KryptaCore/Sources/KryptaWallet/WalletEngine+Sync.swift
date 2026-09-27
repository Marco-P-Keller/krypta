import Foundation
import KryptaBitcoin

extension WalletEngine {
    /// Mit der Blockchain abgleichen.
    ///
    /// Jede eigene Adresse bis zur Lücke hinter der letzten vergebenen oder
    /// benutzten; nur wo sich etwas geändert hat, werden Münzen und Verlauf
    /// neu geholt. Danach: offene Sendungen nachziehen, Zahlungen im Chat prüfen.
    public func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            state.tip = try await chain.tipHeight()
            var changed: [(address: String, path: AddressPath)] = []
            for kind in [WalletKeys.Chain.receive, .change] {
                var index: UInt32 = 0
                // Die Grenze wächst mit jeder benutzten Adresse, die gefunden wird.
                while index < frontier(kind), index < 20_000 {
                    let end = min(index + 5, frontier(kind))
                    let batch = (index..<end).map { (address: address(kind, $0).string, path: AddressPath(chain: kind, index: $0)) }
                    let results = try await fetchStats(batch.map(\.address))
                    for (item, stats) in zip(batch, results) {
                        let old = state.addresses[item.address]?.stats
                        guard stats.txCount > 0 || old != nil else { continue }
                        if old != stats { changed.append(item) }
                        state.addresses[item.address] = .init(path: item.path, stats: stats)
                    }
                    index = end
                }
            }
            if state.deepScan { state.deepScan = false }
            try await refresh(changed)
            await reconcileOutgoing()
            state.lastSync = Date()
            lastError = nil
            save()
            rebuild()
            onChange?()
        } catch let error as ChainError {
            lastError = error.walletFailure
        } catch {
            lastError = .offline
        }
        await refreshFees()
        await verifyClaims()
    }

    /// Nach dem Wiederherstellen oder auf Wunsch: 200 Adressen tief suchen.
    public func deepSync() async {
        state.deepScan = true
        await sync()
    }

    func fetchStats(_ addresses: [String]) async throws -> [AddressStats] {
        let chain = self.chain
        return try await withThrowingTaskGroup(of: (Int, AddressStats).self) { group in
            for (i, a) in addresses.enumerated() {
                group.addTask { (i, try await chain.addressStats(a)) }
            }
            var out = [AddressStats?](repeating: nil, count: addresses.count)
            for try await (i, s) in group { out[i] = s }
            return out.map { $0! }
        }
    }

    /// Münzen und Verlauf der geänderten Adressen neu holen.
    func refresh(_ changed: [(address: String, path: AddressPath)]) async throws {
        guard !changed.isEmpty else { return }
        let chain = self.chain
        var fetched: [(address: String, path: AddressPath, utxos: [ChainUTXO], txs: [ChainTx])] = []
        for start in stride(from: 0, to: changed.count, by: 4) {
            let slice = Array(changed[start..<min(start + 4, changed.count)])
            let part = try await withThrowingTaskGroup(of: (Int, [ChainUTXO], [ChainTx]).self) { group in
                for (i, item) in slice.enumerated() {
                    group.addTask { (i, try await chain.utxos(item.address), try await chain.transactions(item.address)) }
                }
                var out = [(Int, [ChainUTXO], [ChainTx])]()
                for try await r in group { out.append(r) }
                return out.sorted { $0.0 < $1.0 }
            }
            for (i, utxos, txs) in part { fetched.append((slice[i].address, slice[i].path, utxos, txs)) }
        }

        for item in fetched {
            let script = address(item.path.chain, item.path.index).scriptPubKey
            state.coins.removeAll { $0.scriptPubKey == script }
            for u in item.utxos {
                guard let point = try? OutPoint(txid: u.txid, vout: u.vout) else { continue }
                state.coins.append(Coin(outPoint: point, value: u.value, scriptPubKey: script, path: item.path, confirmed: u.height != nil))
            }
            for tx in item.txs { record(tx) }
        }
    }

    /// Eine Transaktion aus Sicht der Wallet: was kam an, was ging weg.
    func record(_ tx: ChainTx) {
        let received = tx.outputs.filter { path(of: $0.script) != nil }.reduce(0) { $0 + $1.value }
        let sent = tx.prevouts.filter { !$0.script.isEmpty && path(of: $0.script) != nil }.reduce(0) { $0 + $1.value }
        let existing = state.history[tx.txid]
        let out = state.outgoing[tx.txid]
        state.history[tx.txid] = WalletTransaction(
            txid: tx.txid,
            net: received - sent,
            fee: sent > 0 ? tx.fee : nil,
            height: tx.height,
            time: existing?.time ?? out?.created ?? tx.blockTime ?? Date(),
            contactId: existing?.contactId ?? out?.contactId ?? state.labels[tx.txid]?.contactId,
            note: existing?.note ?? out?.note ?? state.labels[tx.txid]?.note,
            outgoing: out?.state
        )
    }

    /// Eigene Sendungen, die der Server (noch) nicht zeigt.
    ///
    /// Für jeden Eingang fragen, wer ihn ausgegeben hat: diese Transaktion →
    /// sie ist draußen; eine andere → diese kann nie mehr gelten, die
    /// Münzen sind woanders hin; niemand → dieselbe Transaktion noch einmal
    /// senden. Eine neue, zweite Zahlung entsteht dabei nie.
    func reconcileOutgoing() async {
        for (txid, out) in state.outgoing where out.state != .failed && out.state != .replaced {
            // Gibt es eine eigene Ersatztransaktion, zählt allein, wer die
            // Münzen wirklich ausgegeben hat.
            let replacements = Set(state.outgoing.values.filter { $0.replaces == txid && $0.state != .failed }.map(\.txid))
            if let known = state.history[txid], known.isConfirmed || replacements.isEmpty {
                if out.state != .broadcast { state.outgoing[txid]?.state = .broadcast }
                continue
            }
            var spenders = Set<String>()
            var unknown = false
            for input in out.inputs {
                do {
                    if let by = try await chain.spender(of: input) { spenders.insert(by) }
                } catch {
                    unknown = true
                }
            }
            if unknown { continue }
            if spenders.contains(where: { $0 != txid }) {
                // Ausgegeben von der eigenen Ersatztransaktion: ersetzt, nicht gescheitert.
                if !replacements.isEmpty && spenders.subtracting([txid]).isSubset(of: replacements) {
                    state.outgoing[txid]?.state = .replaced
                    state.history.removeValue(forKey: txid)
                    if let change = out.change { state.coins.removeAll { $0.outPoint == change.outPoint } }
                } else {
                    state.outgoing[txid]?.state = .failed
                }
                continue
            }
            if spenders == [txid] {
                state.outgoing[txid]?.state = .broadcast
                continue
            }
            guard let raw = [UInt8](hex: out.raw) else { continue }
            do {
                if try await chain.broadcast(raw) == txid { state.outgoing[txid]?.state = .broadcast }
            } catch ChainError.rejected(let reason) where reason.lowercased().contains("already") {
                state.outgoing[txid]?.state = .broadcast
            } catch {
                // Bleibt offen; der nächste Abgleich versucht es wieder.
            }
        }
    }

    func refreshFees() async {
        if let targets = try? await chain.feeEstimates(), !targets.isEmpty {
            feeEstimates = FeeEstimates(targets: targets)
        }
        if let prices = try? await chain.prices() {
            if let p = prices[preferredCurrency] {
                fiatRate = (preferredCurrency, p)
            } else if let usd = prices["USD"] {
                fiatRate = ("USD", usd)
            }
        }
    }
}
