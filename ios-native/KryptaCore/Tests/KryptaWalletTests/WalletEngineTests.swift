import Foundation
import XCTest
import KryptaBitcoin
@testable import KryptaWallet

/// Zwei Wallets auf einer Kette im Speicher: Guthaben, Senden, Prüfen,
/// Fehlerfälle. Die Kette prüft jede Signatur wie ein Knoten.
@MainActor
final class WalletEngineTests: XCTestCase {
    var chain: MemoryChain!
    var aliceSecrets: MemoryWalletSecrets!
    var alice: WalletEngine!
    var bob: WalletEngine!
    var aliceStore: MemoryWalletStore!

    override func setUp() async throws {
        chain = MemoryChain(network: .regtest)
        aliceSecrets = MemoryWalletSecrets()
        try aliceSecrets.create()
        let bobSecrets = MemoryWalletSecrets()
        try bobSecrets.create()
        aliceStore = MemoryWalletStore()
        alice = try WalletEngine(network: .regtest, secrets: aliceSecrets, store: aliceStore, chain: chain)
        bob = try WalletEngine(network: .regtest, secrets: bobSecrets, store: MemoryWalletStore(), chain: chain)
    }

    /// Alice bekommt `sats` von außen, bestätigt.
    func fundAlice(_ sats: Int64) async {
        chain.fund(alice.receiveAddress().string, sats)
        chain.mine()
        await alice.sync()
    }

    func testReceiveAndConfirm() async throws {
        let address = alice.receiveAddress()
        XCTAssertEqual(alice.receiveAddress(), address, "bleibt, bis etwas eingeht")
        chain.fund(address.string, 250_000)
        await alice.sync()
        XCTAssertEqual(alice.balance.incoming, 250_000)
        XCTAssertEqual(alice.balance.confirmed, 0)
        XCTAssertEqual(alice.transactions.first?.net, 250_000)
        XCTAssertFalse(alice.transactions.first!.isConfirmed)

        chain.mine()
        await alice.sync()
        XCTAssertEqual(alice.balance.confirmed, 250_000)
        XCTAssertEqual(alice.balance.incoming, 0)
        XCTAssertTrue(alice.transactions.first!.isConfirmed)
        XCTAssertNotEqual(alice.receiveAddress(), address, "benutzt: nächste Adresse")
        XCTAssertNil(alice.lastError)
    }

    func testEachContactGetsOwnAddress() async throws {
        let forBob = try XCTUnwrap(alice.chatAddress(for: "bob"))
        let forCarol = try XCTUnwrap(alice.chatAddress(for: "carol"))
        XCTAssertNotEqual(forBob, forCarol)
        XCTAssertEqual(alice.chatAddress(for: "bob"), forBob)
        XCTAssertNotEqual(alice.receiveAddress().string, forBob)
        alice.chatPaymentsEnabled = false
        XCTAssertNil(alice.chatAddress(for: "bob"))
    }

    /// Der ganze Weg: Alice zahlt an Bobs Chat-Adresse, Bob prüft die
    /// Behauptung aus dem Chat gegen die Kette.
    func testPayContactAndVerifyClaim() async throws {
        await fundAlice(1_000_000)
        await alice.sync()
        XCTAssertEqual(alice.feeEstimates, FeeEstimates(fast: 15, normal: 8, slow: 3))

        let bobAddress = try XCTUnwrap(bob.chatAddress(for: "alice"))
        let recipient = try XCTUnwrap(alice.parseAddress(bobAddress))
        let draft = try alice.prepare(to: recipient, amount: .exact(300_000), feeLevel: .normal, contactId: "bob", note: "Pizza")
        XCTAssertEqual(draft.fee, 141 * 8)
        let sent = try await alice.send(draft, reason: "test")
        XCTAssertEqual(aliceSecrets.prompts, 1, "genau eine Rückfrage")
        XCTAssertEqual(sent.payment.sats, 300_000)
        XCTAssertEqual(sent.payment.address, bobAddress)
        XCTAssertTrue(chain.contains(sent.txid))
        XCTAssertEqual(alice.balance.confirmed, 0)
        XCTAssertEqual(alice.balance.ownPending, 1_000_000 - 300_000 - draft.fee)
        XCTAssertEqual(alice.outgoingState(sent.txid)?.state, .broadcast)
        XCTAssertEqual(alice.transactions.first?.contactId, "bob")
        XCTAssertEqual(alice.transactions.first?.net, -(300_000 + draft.fee))

        // Bob: erst unbestätigt, nach dem Block bestätigt und bewiesen.
        bob.registerClaim(sent.payment, from: "alice", messageId: "m1", note: "Pizza")
        await waitFor { self.bob.claimStatus(messageId: "m1") != .checking }
        XCTAssertEqual(bob.claimStatus(messageId: "m1"), .unconfirmed(received: 300_000))
        XCTAssertNotEqual(bob.chatAddress(for: "alice"), bobAddress, "benutzte Adresse wird ersetzt")

        chain.mine()
        await bob.sync()
        guard case .confirmed(300_000, _, true)? = bob.claimStatus(messageId: "m1") else {
            return XCTFail("\(String(describing: bob.claimStatus(messageId: "m1")))")
        }
        XCTAssertEqual(bob.balance.confirmed, 300_000)
        XCTAssertEqual(bob.transactions.first?.contactId, "alice")
        XCTAssertEqual(bob.transactions.first?.note, "Pizza")

        // Alice kann ihr Wechselgeld weiter ausgeben.
        await alice.sync()
        XCTAssertEqual(alice.balance.confirmed, 1_000_000 - 300_000 - draft.fee)
        let again = try alice.prepare(to: recipient, amount: .all, feeRate: 2)
        _ = try await alice.send(again, reason: "test")
        chain.mine()
        await alice.sync()
        XCTAssertEqual(alice.balance.total, 0)
    }

    /// Behauptungen, die nicht stimmen, werden nicht als Geld angezeigt.
    func testFakeClaimsAreExposed() async throws {
        await fundAlice(500_000)
        let bobAddress = try XCTUnwrap(bob.chatAddress(for: "alice"))
        let draft = try alice.prepare(to: XCTUnwrap(alice.parseAddress(bobAddress)), amount: .exact(10_000), feeRate: 2)
        let sent = try await alice.send(draft, reason: "test")

        // Mehr behaupten, als gezahlt wurde.
        let inflated = ChatPayment(txid: sent.txid, vout: sent.payment.vout, sats: 1_000_000, address: bobAddress, network: .regtest)
        bob.registerClaim(inflated, from: "alice", messageId: "inflated")
        // Eine fremde Zahlung als eigene ausgeben (Adresse gehört nicht Bob).
        let foreign = ChatPayment(txid: sent.txid, vout: sent.payment.vout, sats: 10_000, address: alice.receiveAddress().string, network: .regtest)
        bob.registerClaim(foreign, from: "alice", messageId: "foreign")
        // Die Wechselgeld-Ausgabe als Zahlung an Bob ausgeben.
        let wrongVout = ChatPayment(txid: sent.txid, vout: 1 - sent.payment.vout, sats: 10_000, address: bobAddress, network: .regtest)
        bob.registerClaim(wrongVout, from: "alice", messageId: "vout")
        // Erfunden.
        let invented = ChatPayment(txid: String(repeating: "ab", count: 32), vout: 0, sats: 10_000, address: bobAddress, network: .regtest)
        bob.registerClaim(invented, from: "alice", messageId: "invented")
        // Testnetz-Münzen im Regtest-Chat.
        bob.registerClaim(ChatPayment(txid: sent.txid, vout: 0, sats: 1, address: "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl", network: .testnet4),
                          from: "alice", messageId: "net")

        await waitFor { ["inflated", "foreign", "vout"].allSatisfy { self.bob.claimStatus(messageId: $0) != .checking } }
        XCTAssertEqual(bob.claimStatus(messageId: "inflated"), .mismatch(received: 10_000))
        XCTAssertEqual(bob.claimStatus(messageId: "foreign"), .mismatch(received: 0))
        XCTAssertEqual(bob.claimStatus(messageId: "vout"), .mismatch(received: 0))
        XCTAssertEqual(bob.claimStatus(messageId: "invented"), .checking, "noch nicht gefunden, aber nie als Geld")
        XCTAssertEqual(bob.claimStatus(messageId: "net"), .otherNetwork)
    }

    /// Wer mit erfundenen Zahlungen flutet, blockiert nur seine eigenen.
    func testClaimSpamOnlyBlocksTheSpammer() async throws {
        await fundAlice(100_000)
        for i in 0..<25 {
            let fake = ChatPayment(txid: Hashes.sha256(Array("fake\(i)".utf8)).hex, vout: 0, sats: 1000,
                                   address: try XCTUnwrap(bob.chatAddress(for: "mallory")), network: .regtest)
            bob.registerClaim(fake, from: "mallory", messageId: "spam\(i)")
        }
        XCTAssertNil(bob.claimStatus(messageId: "spam20"), "mehr als zehn offene je Kontakt werden nicht geprüft")
        let draft = try alice.prepare(to: XCTUnwrap(alice.parseAddress(XCTUnwrap(bob.chatAddress(for: "alice")))), amount: .exact(5_000), feeRate: 2)
        let sent = try await alice.send(draft, reason: "test")
        bob.registerClaim(sent.payment, from: "alice", messageId: "real")
        await waitFor { self.bob.claimStatus(messageId: "real") != .checking }
        XCTAssertEqual(bob.claimStatus(messageId: "real"), .unconfirmed(received: 5_000))
    }

    /// Netzfehler beim Senden: die Münzen bleiben gesperrt, es entsteht keine
    /// zweite Zahlung, und der Abgleich findet die erste.
    func testUncertainBroadcastNeverPaysTwice() async throws {
        await fundAlice(100_000)
        let to = try XCTUnwrap(bob.parseAddress(bob.receiveAddress().string))
        let draft = try alice.prepare(to: to, amount: .exact(50_000), feeRate: 3)
        chain.dropBroadcastReply = true
        do {
            _ = try await alice.send(draft, reason: "test")
            XCTFail("sollte unklar sein")
        } catch WalletFailure.broadcastUncertain(let txid) {
            XCTAssertTrue(chain.contains(txid), "kam doch an")
            XCTAssertEqual(alice.outgoingState(txid)?.state, .uncertain)
            XCTAssertEqual(alice.balance.spendable, 0, "Münze gesperrt")
            XCTAssertThrowsError(try alice.prepare(to: to, amount: .exact(50_000), feeRate: 3), "keine zweite Zahlung möglich")
            await alice.sync()
            XCTAssertEqual(alice.outgoingState(txid)?.state, .broadcast)
            XCTAssertEqual(chain.broadcasts, 1)
        }
    }

    /// Unklar und nie angekommen: derselbe Abgleich sendet genau dieselbe Transaktion.
    func testUncertainBroadcastIsRetriedIdentically() async throws {
        await fundAlice(100_000)
        let to = try XCTUnwrap(bob.parseAddress(bob.receiveAddress().string))
        let draft = try alice.prepare(to: to, amount: .exact(40_000), feeRate: 3)
        chain.failure = .unreachable
        do {
            _ = try await alice.send(draft, reason: "test")
            XCTFail("sollte unklar sein")
        } catch WalletFailure.broadcastUncertain(let txid) {
            XCTAssertFalse(chain.contains(txid))
            chain.failure = nil
            await alice.sync()
            XCTAssertTrue(chain.contains(txid), "dieselbe Kennung, also dieselbe Transaktion")
            XCTAssertEqual(alice.outgoingState(txid)?.state, .broadcast)
        }
    }

    func testRejectedBroadcastFreesCoins() async throws {
        await fundAlice(100_000)
        let to = try XCTUnwrap(bob.parseAddress(bob.receiveAddress().string))
        let draft = try alice.prepare(to: to, amount: .exact(40_000), feeRate: 3)
        chain.failure = .rejected("min relay fee not met")
        do {
            _ = try await alice.send(draft, reason: "test")
            XCTFail("sollte abgelehnt werden")
        } catch WalletFailure.rejected {
            XCTAssertEqual(alice.balance.spendable, 100_000)
        }
        chain.failure = nil
        XCTAssertNoThrow(try alice.prepare(to: to, amount: .exact(40_000), feeRate: 3))
    }

    func testCancelledAuthenticationSendsNothing() async throws {
        await fundAlice(100_000)
        let draft = try alice.prepare(to: XCTUnwrap(bob.parseAddress(bob.receiveAddress().string)), amount: .exact(40_000), feeRate: 3)
        aliceSecrets.cancelNext = true
        do {
            _ = try await alice.send(draft, reason: "test")
            XCTFail("abgebrochen")
        } catch {
            XCTAssertEqual(error as? WalletFailure, .authenticationCancelled)
        }
        XCTAssertEqual(chain.broadcasts, 0)
        XCTAssertEqual(alice.balance.spendable, 100_000)
    }

    func testStaleDraftIsRefused() async throws {
        await fundAlice(100_000)
        let to = try XCTUnwrap(bob.parseAddress(bob.receiveAddress().string))
        let first = try alice.prepare(to: to, amount: .exact(40_000), feeRate: 3)
        let second = try alice.prepare(to: to, amount: .exact(30_000), feeRate: 3)
        _ = try await alice.send(first, reason: "test")
        do {
            _ = try await alice.send(second, reason: "test")
            XCTFail("dieselbe Münze zweimal")
        } catch {
            XCTAssertEqual(error as? WalletFailure, .stale)
        }
    }

    func testInsufficientFundsAndDust() async throws {
        await fundAlice(10_000)
        let to = try XCTUnwrap(bob.parseAddress(bob.receiveAddress().string))
        XCTAssertThrowsError(try alice.prepare(to: to, amount: .exact(20_000), feeRate: 1)) {
            XCTAssertEqual($0 as? WalletFailure, .insufficientFunds(available: 10_000 - 110))
        }
        XCTAssertThrowsError(try alice.prepare(to: to, amount: .exact(100), feeRate: 1)) {
            XCTAssertEqual($0 as? WalletFailure, .amountBelowDust(minimum: 294))
        }
        let mainnetAddress = try BitcoinAddress("bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu", network: .mainnet)
        XCTAssertThrowsError(try alice.prepare(to: mainnetAddress, amount: .exact(1000), feeRate: 1)) {
            XCTAssertEqual($0 as? WalletFailure, .wrongNetwork)
        }
    }

    /// Wiederherstellen aus den Wörtern: dieselben Adressen, und dank tiefer
    /// Suche auch Geld an Adresse 150 (viele Kontakte, keiner zahlte).
    func testRestoreFindsFundsFarAway() async throws {
        let words = try await alice.recoveryWords(reason: "test")
        XCTAssertEqual(words.count, 12)
        for i in 0..<150 { _ = alice.chatAddress(for: "contact\(i)") }
        let far = try XCTUnwrap(alice.chatAddress(for: "late"))
        chain.fund(far, 77_000)
        chain.mine()

        let restored = try MemoryWalletSecrets(words: words)
        let fresh = try WalletEngine(network: .regtest, secrets: restored, store: MemoryWalletStore(), chain: chain)
        await fresh.sync()
        XCTAssertEqual(fresh.balance.total, 0, "normale Lücke von 20 reicht nicht")
        await fresh.deepSync()
        XCTAssertEqual(fresh.balance.confirmed, 77_000)
    }

    func testStatePersists() async throws {
        await fundAlice(123_000)
        let bobAddress = alice.chatAddress(for: "bob")
        alice.confirmBackup()
        let reopened = try WalletEngine(network: .regtest, secrets: aliceSecrets, store: aliceStore, chain: chain)
        XCTAssertEqual(reopened.balance.confirmed, 123_000)
        XCTAssertEqual(reopened.chatAddress(for: "bob"), bobAddress)
        XCTAssertTrue(reopened.backedUp)
        // Anderes Netz, anderer Stand.
        XCTAssertThrowsError(try WalletEngine(network: .mainnet, secrets: MemoryWalletSecrets(), store: aliceStore, chain: chain))
    }

    func testFeeEstimatesAreOrderedAndCapped() async {
        let e = FeeEstimates(targets: [1: 5000, 2: 3, 3: 4, 6: 9, 24: 0.4, 144: 0.1])
        XCTAssertEqual(e.slow, 1)
        XCTAssertEqual(e.normal, 9)
        XCTAssertEqual(e.fast, 9, "nie billiger als normal")
        let capped = FeeEstimates(targets: [1: 5000, 2: 4000, 6: 2000, 24: 1500])
        XCTAssertEqual(capped.fast, 1000)
        XCTAssertEqual(FeeEstimates(targets: [:]).normal, 1)
    }

    func testChatPaymentParsing() async {
        let ok = ChatPayment.parse(txid: String(repeating: "a", count: 64), vout: 1, sats: 5000, address: "bcrt1q9u62588spffmq4dzjxsr5l297znf3z6jkgnhsw", network: "regtest")
        XCTAssertNotNil(ok)
        XCTAssertNil(ChatPayment.parse(txid: "xyz", vout: 1, sats: 5000, address: "bcrt1q9u62588spffmq4dzjxsr5l297znf3z6jkgnhsw", network: "regtest"))
        XCTAssertNil(ChatPayment.parse(txid: String(repeating: "a", count: 64), vout: 1, sats: -5, address: "bcrt1q9u62588spffmq4dzjxsr5l297znf3z6jkgnhsw", network: "regtest"))
        XCTAssertNil(ChatPayment.parse(txid: String(repeating: "a", count: 64), vout: 1, sats: 5000, address: "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu", network: "regtest"))
        XCTAssertNil(ChatPayment.parse(txid: String(repeating: "a", count: 64), vout: 1, sats: 5000, address: "bcrt1q9u62588spffmq4dzjxsr5l297znf3z6jkgnhsw", network: "mars"))
    }

    func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
