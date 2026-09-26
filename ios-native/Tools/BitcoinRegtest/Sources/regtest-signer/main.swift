import Foundation
import KryptaBitcoin

// Liest einen Auftrag (JSON) von stdin, plant und signiert mit KryptaBitcoin,
// schreibt das Ergebnis (JSON) nach stdout. Nur für den Regtest-Abgleich.
struct Job: Decodable {
    struct C: Decodable { let txid: String; let vout: UInt32; let value: Int64; let chain: UInt32; let index: UInt32; let confirmed: Bool? }
    let words: String
    let coins: [C]
    let recipient: String
    let amount: Int64?
    let feeRate: Double
    let changeIndex: UInt32
    let lockTime: UInt32
}
let job = try JSONDecoder().decode(Job.self, from: FileHandle.standardInput.readDataToEndOfFile())
let seed = Mnemonic.seed(words: job.words.split(separator: " ").map(String.init)).copy
let net = BitcoinNetwork.regtest
let account = try WalletKeys.account(seed: seed, network: net)
if job.coins.isEmpty {
    // Nur Adressen ausgeben.
    var out: [String: [String]] = ["receive": [], "change": []]
    for i in 0..<20 {
        out["receive"]!.append(try WalletKeys.address(account: account, chain: .receive, index: UInt32(i), network: net).string)
        out["change"]!.append(try WalletKeys.address(account: account, chain: .change, index: UInt32(i), network: net).string)
    }
    print(String(decoding: try JSONEncoder().encode(out), as: UTF8.self))
    exit(0)
}
let coins = try job.coins.map { c -> Coin in
    let chain = WalletKeys.Chain(rawValue: c.chain)!
    let addr = try WalletKeys.address(account: account, chain: chain, index: c.index, network: net)
    return Coin(outPoint: try OutPoint(txid: c.txid, vout: c.vout), value: c.value, scriptPubKey: addr.scriptPubKey, path: AddressPath(chain: chain, index: c.index), confirmed: c.confirmed ?? true)
}
let recipient = try BitcoinAddress(job.recipient, network: net)
let change = try WalletKeys.address(account: account, chain: .change, index: job.changeIndex, network: net)
var rng = SystemRandomNumberGenerator()
do {
    let plan = try TransactionPlanner.plan(coins: coins, recipient: recipient.scriptPubKey, amount: job.amount.map { .exact($0) } ?? .all,
                                           feeRate: job.feeRate, changeScript: change.scriptPubKey, changePath: AddressPath(chain: .change, index: job.changeIndex), using: &rng)
    let tx = try TransactionSigner.sign(plan.unsignedTransaction(lockTime: job.lockTime), inputs: plan.signerInputs, seed: seed, network: net)
    let out: [String: Any] = ["hex": tx.serialized().hex, "txid": tx.txid, "fee": plan.fee, "estimatedVSize": plan.estimatedVSize,
                              "vsize": tx.virtualSize, "recipientIndex": plan.recipientIndex, "changeIndex": plan.changeIndex ?? -1,
                              "inputs": plan.inputs.count, "amount": plan.amount]
    print(String(decoding: try JSONSerialization.data(withJSONObject: out), as: UTF8.self))
} catch {
    print("{\"error\": \"\(error)\"}")
}
