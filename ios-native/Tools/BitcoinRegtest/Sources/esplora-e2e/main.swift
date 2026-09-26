import Foundation
import KryptaBitcoin
import KryptaWallet
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Zwei Wallets gegen Esplora (esplora_mock.py über bitcoind -regtest):
// EsploraClient, Abgleich, Senden, Prüfen mit echtem Merkle-Beweis.
@MainActor
func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { exit(1) }
}

@MainActor
func mine(_ n: Int, to address: String) async {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:3002/_mine?n=\(n)&address=\(address)")!)
    req.httpMethod = "POST"
    _ = try? await URLSession.shared.data(for: req)
}

@MainActor
func run() async throws {
    let base = URL(string: "http://127.0.0.1:3002")!
    let aSecrets = MemoryWalletSecrets(); try aSecrets.create()
    let bSecrets = MemoryWalletSecrets(); try bSecrets.create()
    let a = try WalletEngine(network: .regtest, secrets: aSecrets, store: MemoryWalletStore(), chain: EsploraClient(baseURL: base))
    let b = try WalletEngine(network: .regtest, secrets: bSecrets, store: MemoryWalletStore(), chain: EsploraClient(baseURL: base))
    let burn = "bcrt1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080"

    // Eine reife Coinbase für A.
    await mine(1, to: a.receiveAddress().string)
    await mine(100, to: burn)
    await a.sync()
    check(a.lastError == nil, "Abgleich ohne Fehler (\(String(describing: a.lastError)))")
    check(a.balance.confirmed == 5_000_000_000, "Guthaben 50 BTC: \(a.balance.confirmed)")
    check(a.feeEstimates == FeeEstimates(fast: 4, normal: 2, slow: 1.2), "Gebühren: \(String(describing: a.feeEstimates))")
    check(a.fiatRate?.price == 100_000, "Kurs")
    check(a.transactions.count == 1 && a.transactions[0].isConfirmed, "Verlauf: Coinbase bestätigt")

    // A zahlt an B (Chat-Adresse), mit Wechselgeld.
    let bAddr = try b.chatAddress(for: "a").flatMap(a.parseAddress) ?? { fatalError() }()
    let draft = try a.prepare(to: bAddr, amount: .exact(100_000_000), feeLevel: .normal, contactId: "b", note: "Test")
    let sent = try await a.send(draft, reason: "e2e")
    check(sent.payment.sats == 100_000_000, "gesendet: \(sent.txid)")
    b.registerClaim(sent.payment, from: "a", messageId: "m1")
    for _ in 0..<100 where b.claimStatus(messageId: "m1") == .checking { try await Task.sleep(for: .milliseconds(50)) }
    check(b.claimStatus(messageId: "m1") == .unconfirmed(received: 100_000_000), "B sieht die Zahlung unbestätigt: \(String(describing: b.claimStatus(messageId: "m1")))")
    await b.sync()
    check(b.balance.incoming == 100_000_000, "B: unterwegs \(b.balance.incoming)")

    await mine(1, to: burn)
    await b.sync()
    guard case .confirmed(100_000_000, _, true)? = b.claimStatus(messageId: "m1") else {
        return check(false, "B: bestätigt mit Merkle-Beweis: \(String(describing: b.claimStatus(messageId: "m1")))")
    }
    check(true, "B: bestätigt, Merkle-Beweis gegen echten Blockkopf geprüft")
    check(b.balance.confirmed == 100_000_000, "B: Guthaben 1 BTC")
    await a.sync()
    check(a.balance.confirmed == 5_000_000_000 - 100_000_000 - draft.fee, "A: Wechselgeld bestätigt \(a.balance.confirmed)")
    check(a.transactions.first?.contactId == "b" && a.transactions.first?.net == -(100_000_000 + draft.fee), "A: Verlauf mit Kontakt")

    // B schickt alles zurück (eigene bestätigte Münze), A empfängt.
    let back = try b.prepare(to: a.receiveAddress(), amount: .all, feeLevel: .fast)
    _ = try await b.send(back, reason: "e2e")
    await mine(1, to: burn)
    await b.sync(); await a.sync()
    check(b.balance.total == 0, "B: leer")
    check(a.balance.confirmed == 5_000_000_000 - draft.fee - back.fee, "A: alles zurück")

    // Ein Server, der ablehnt: Doppelausgabe derselben Münze.
    let first = try a.prepare(to: bAddr, amount: .exact(10_000), feeRate: 2)
    let second = try a.prepare(to: bAddr, amount: .exact(20_000), feeRate: 2)
    _ = try await a.send(first, reason: "e2e")
    do { _ = try await a.send(second, reason: "e2e"); check(false, "Doppelausgabe") } catch { check((error as? WalletFailure) == .stale, "zweiter Entwurf mit derselben Münze abgewiesen") }
    print("ALLE OK")
}

@main
struct E2E {
    static func main() async {
        do { try await run() } catch { print("FEHLER \(error)"); exit(1) }
        exit(0)
    }
}
