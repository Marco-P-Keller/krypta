import Foundation
import KryptaBitcoin

/// Eine Blockchain im Speicher — für Tests und den Demo-Modus.
///
/// Sie prüft, was hereinkommt, wie ein echter Knoten es in den Punkten tun
/// würde, auf die es hier ankommt: Eingänge existieren und sind unverbraucht,
/// jede P2WPKH-Signatur stimmt (BIP143), keine Ausgabe ist Staub, die Summe
/// geht auf. Blöcke haben echte Merkle-Wurzeln und Köpfe mit (leichter) Arbeit.
public final class MemoryChain: ChainSource, @unchecked Sendable {
    public let network: BitcoinNetwork
    private let lock = NSLock()

    private struct Entry {
        var tx: Transaction
        var prevouts: [ChainTxOutput]
        var height: Int?
        var time: Date
    }

    private var txs: [String: Entry] = [:]
    private var order: [String] = []
    private var spent: [OutPoint: String] = [:]
    private var blocks: [(header: [UInt8], txids: [String])] = []
    private var fundingCounter = 0

    /// Für Tests: jede Anfrage schlägt fehl, solange gesetzt.
    public var failure: ChainError?
    /// Für Tests: das nächste Senden kommt an, meldet aber einen Netzfehler.
    public var dropBroadcastReply = false
    public var estimates: [Int: Double] = [1: 20, 2: 15, 3: 12, 6: 8, 24: 3, 144: 1]
    public private(set) var broadcasts = 0

    public init(network: BitcoinNetwork = .regtest) {
        self.network = network
        // Genesis: ein leerer Block.
        blocks.append((Self.header(prev: [UInt8](repeating: 0, count: 32), root: [UInt8](repeating: 0, count: 32), time: 0), []))
    }

    // MARK: - Steuerung für Tests

    /// Legt Geld an eine Adresse (wie eine Zahlung von außen) in den Mempool.
    @discardableResult
    public func fund(_ address: String, _ value: Int64) -> String {
        lock.withLock {
            fundingCounter += 1
            let script = (try? BitcoinAddress(address, network: network).scriptPubKey) ?? []
            let source = OutPointSeed.make(fundingCounter)
            let tx = Transaction(inputs: [TxInput(outPoint: source, scriptSig: [0x51], sequence: 0xFFFF_FFFF)],
                                 outputs: [TxOutput(value: value, scriptPubKey: script)])
            let txid = tx.txid
            txs[txid] = Entry(tx: tx, prevouts: [ChainTxOutput(script: [0x51], value: value + 500)], height: nil, time: Date())
            order.append(txid)
            return txid
        }
    }

    /// Alles aus dem Mempool in einen Block.
    public func mine(_ count: Int = 1) {
        lock.withLock {
            for _ in 0..<count {
                let pending = order.filter { txs[$0]?.height == nil }
                let height = blocks.count
                for id in pending { txs[id]?.height = height }
                let root = Self.merkleRoot(pending)
                let prev = Hashes.hash256(blocks.last!.header)
                blocks.append((Self.header(prev: prev, root: root, time: UInt32(Date().timeIntervalSince1970)), pending))
            }
        }
    }

    public var mempoolCount: Int { lock.withLock { txs.values.filter { $0.height == nil }.count } }

    public func contains(_ txid: String) -> Bool { lock.withLock { txs[txid] != nil } }

    // MARK: - ChainSource

    private func check() throws {
        if let failure { throw failure }
    }

    public func tipHeight() async throws -> Int {
        try check()
        return lock.withLock { blocks.count - 1 }
    }

    private func touches(_ entry: Entry, _ script: [UInt8]) -> Bool {
        entry.tx.outputs.contains { $0.scriptPubKey == script } || entry.prevouts.contains { $0.script == script }
    }

    private func script(_ address: String) throws -> [UInt8] {
        guard let s = try? BitcoinAddress(address, network: network).scriptPubKey else { throw ChainError.rejected("address") }
        return s
    }

    public func addressStats(_ address: String) async throws -> AddressStats {
        try check()
        let s = try script(address)
        return lock.withLock {
            var count = 0, pending = 0, funded: Int64 = 0, spentSum: Int64 = 0
            for entry in txs.values where touches(entry, s) {
                count += 1
                if entry.height == nil { pending += 1 }
                funded += entry.tx.outputs.filter { $0.scriptPubKey == s }.reduce(0) { $0 + $1.value }
                spentSum += entry.prevouts.filter { $0.script == s }.reduce(0) { $0 + $1.value }
            }
            return AddressStats(txCount: count, pendingCount: pending, funded: funded, spent: spentSum)
        }
    }

    public func utxos(_ address: String) async throws -> [ChainUTXO] {
        try check()
        let s = try script(address)
        return lock.withLock {
            var out = [ChainUTXO]()
            for id in order {
                guard let entry = txs[id] else { continue }
                for (i, o) in entry.tx.outputs.enumerated() where o.scriptPubKey == s {
                    let point = try! OutPoint(txid: id, vout: UInt32(i))
                    if spent[point] == nil { out.append(ChainUTXO(txid: id, vout: UInt32(i), value: o.value, height: entry.height)) }
                }
            }
            return out
        }
    }

    public func transactions(_ address: String) async throws -> [ChainTx] {
        try check()
        let s = try script(address)
        return lock.withLock {
            order.reversed().compactMap { id -> ChainTx? in
                guard let e = txs[id], touches(e, s) else { return nil }
                let fee = e.prevouts.reduce(0) { $0 + $1.value } - e.tx.outputs.reduce(0) { $0 + $1.value }
                return ChainTx(txid: id, prevouts: e.prevouts, outputs: e.tx.outputs.map { ChainTxOutput(script: $0.scriptPubKey, value: $0.value) },
                               fee: fee, height: e.height, blockTime: e.height == nil ? nil : e.time)
            }
        }
    }

    public func rawTransaction(_ txid: String) async throws -> [UInt8] {
        try check()
        guard let e = lock.withLock({ txs[txid] }) else { throw ChainError.notFound }
        return e.tx.serialized()
    }

    public func status(_ txid: String) async throws -> TxStatus {
        try check()
        return try lock.withLock {
            guard let e = txs[txid] else { throw ChainError.notFound }
            guard let h = e.height else { return TxStatus(confirmed: false, height: nil, blockHash: nil) }
            return TxStatus(confirmed: true, height: h, blockHash: Array(Hashes.hash256(blocks[h].header).reversed()).hex)
        }
    }

    public func spender(of outPoint: OutPoint) async throws -> String? {
        try check()
        return lock.withLock { spent[outPoint] }
    }

    public func merkleProof(_ txid: String) async throws -> MerkleProofData {
        try check()
        return try lock.withLock {
            guard let h = txs[txid]?.height, let pos = blocks[h].txids.firstIndex(of: txid) else { throw ChainError.notFound }
            return MerkleProofData(height: h, siblings: Self.branch(blocks[h].txids, pos), position: pos)
        }
    }

    public func blockHeader(_ hash: String) async throws -> [UInt8] {
        try check()
        return try lock.withLock {
            guard let b = blocks.first(where: { Array(Hashes.hash256($0.header).reversed()).hex == hash }) else { throw ChainError.notFound }
            return b.header
        }
    }

    public func feeEstimates() async throws -> [Int: Double] {
        try check()
        return estimates
    }

    public func prices() async throws -> [String: Double] {
        try check()
        return ["USD": 100_000, "EUR": 92_000, "CHF": 86_000]
    }

    public func broadcast(_ raw: [UInt8]) async throws -> String {
        try check()
        let tx: Transaction
        do { tx = try Transaction.parse(raw) } catch { throw ChainError.rejected("decode") }
        let txid = tx.txid
        let reply: String = try lock.withLock {
            if txs[txid] != nil { return txid }
            var prevouts = [ChainTxOutput]()
            var inputs = [TransactionSigner.Input]()
            var conflicts = Set<String>()
            for input in tx.inputs {
                guard let parent = txs[input.outPoint.txid], Int(input.outPoint.vout) < parent.tx.outputs.count else {
                    throw ChainError.rejected("missing-inputs")
                }
                if let other = spent[input.outPoint] { conflicts.insert(other) }
                let out = parent.tx.outputs[Int(input.outPoint.vout)]
                prevouts.append(ChainTxOutput(script: out.scriptPubKey, value: out.value))
                inputs.append(.init(outPoint: input.outPoint, value: out.value, scriptPubKey: out.scriptPubKey, path: AddressPath(chain: .receive, index: 0)))
            }
            do { try TransactionSigner.verify(tx, inputs: inputs) } catch { throw ChainError.rejected("mandatory-script-verify-flag-failed") }
            let inSum = prevouts.reduce(0) { $0 + $1.value }, outSum = tx.outputs.reduce(0) { $0 + $1.value }
            guard outSum <= inSum else { throw ChainError.rejected("bad-txns-in-belowout") }
            guard inSum - outSum >= Int64(tx.virtualSize) else { throw ChainError.rejected("min relay fee not met") }
            guard tx.outputs.allSatisfy({ $0.value >= BitcoinAddress.dustLimit(scriptPubKey: $0.scriptPubKey) }) else { throw ChainError.rejected("dust") }
            if !conflicts.isEmpty {
                // Replace-by-Fee wie Bitcoin Core (BIP125): nur unbestätigte,
                // als ersetzbar markierte Vorgänger; mehr Gebühr insgesamt,
                // mindestens 1 sat/vB auf die neue Größe mehr, höherer Satz;
                // keine neuen unbestätigten Eingänge.
                let fee = inSum - outSum
                var oldFees: Int64 = 0
                for c in conflicts {
                    guard let old = txs[c], old.height == nil, old.tx.inputs.contains(where: { $0.sequence < 0xFFFF_FFFE }) else {
                        throw ChainError.rejected("txn-mempool-conflict")
                    }
                    let oldFee = old.prevouts.reduce(0) { $0 + $1.value } - old.tx.outputs.reduce(0) { $0 + $1.value }
                    oldFees += oldFee
                    guard Double(fee) / Double(tx.virtualSize) > Double(oldFee) / Double(old.tx.virtualSize) else {
                        throw ChainError.rejected("insufficient fee, rejecting replacement")
                    }
                }
                guard fee >= oldFees + Int64(tx.virtualSize) else { throw ChainError.rejected("insufficient fee, rejecting replacement") }
                let originalInputs = Set(conflicts.flatMap { txs[$0]!.tx.inputs.map(\.outPoint) })
                for input in tx.inputs where !originalInputs.contains(input.outPoint) && txs[input.outPoint.txid]?.height == nil {
                    throw ChainError.rejected("replacement-adds-unconfirmed")
                }
                // Die ersetzten samt allem, was auf ihnen aufbaut, fliegen raus.
                var evict = conflicts
                var grew = true
                while grew {
                    grew = false
                    for (id, entry) in txs where entry.height == nil && !evict.contains(id)
                        && entry.tx.inputs.contains(where: { evict.contains($0.outPoint.txid) }) {
                        evict.insert(id)
                        grew = true
                    }
                }
                for id in evict {
                    for input in txs[id]!.tx.inputs where spent[input.outPoint] == id { spent.removeValue(forKey: input.outPoint) }
                    txs.removeValue(forKey: id)
                    order.removeAll { $0 == id }
                }
            }
            for input in tx.inputs { spent[input.outPoint] = txid }
            txs[txid] = Entry(tx: tx, prevouts: prevouts, height: nil, time: Date())
            order.append(txid)
            broadcasts += 1
            return txid
        }
        if dropBroadcastReply {
            dropBroadcastReply = false
            throw ChainError.unreachable
        }
        return reply
    }

    // MARK: - Blöcke

    static func header(prev: [UInt8], root: [UInt8], time: UInt32) -> [UInt8] {
        var nonce: UInt32 = 0
        while true {
            var h = [UInt8]()
            h.appendLittleEndian(UInt32(0x2000_0000))
            h += prev + root
            h.appendLittleEndian(time)
            h.appendLittleEndian(UInt32(0x207F_FFFF))
            h.appendLittleEndian(nonce)
            if let header = try? BlockHeader(h), header.hasProofOfWork(maximumTarget: [UInt8](repeating: 0xFF, count: 32)) { return h }
            nonce += 1
        }
    }

    static func merkleRoot(_ txids: [String]) -> [UInt8] {
        var level = txids.map { Array([UInt8](hex: $0)!.reversed()) }
        guard !level.isEmpty else { return [UInt8](repeating: 0, count: 32) }
        while level.count > 1 {
            if level.count % 2 == 1 { level.append(level.last!) }
            level = stride(from: 0, to: level.count, by: 2).map { Hashes.hash256(level[$0] + level[$0 + 1]) }
        }
        return level[0]
    }

    static func branch(_ txids: [String], _ index: Int) -> [String] {
        var level = txids.map { Array([UInt8](hex: $0)!.reversed()) }
        var i = index
        var out = [String]()
        while level.count > 1 {
            if level.count % 2 == 1 { level.append(level.last!) }
            out.append(Array(level[i ^ 1].reversed()).hex)
            level = stride(from: 0, to: level.count, by: 2).map { Hashes.hash256(level[$0] + level[$0 + 1]) }
            i /= 2
        }
        return out
    }
}

private enum OutPointSeed {
    static func make(_ n: Int) -> OutPoint {
        try! OutPoint(txid: Hashes.sha256(Array("krypta-demo-\(n)".utf8)).hex, vout: 0)
    }
}

extension Array where Element == UInt8 {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
