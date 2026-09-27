import Foundation
import XCTest
import KryptaBitcoin
@testable import KryptaWallet

/// Gebühr erhöhen (Replace-by-Fee, BIP125). Die Kette im Speicher nimmt
/// Ersatztransaktionen nach denselben Regeln an wie Bitcoin Core.
@MainActor
final class FeeBumpTests: XCTestCase {
    var chain: MemoryChain!
    var alice: WalletEngine!
    var bob: WalletEngine!

    override func setUp() async throws {
        chain = MemoryChain(network: .regtest)
        let a = MemoryWalletSecrets()
        try a.create()
        let b = MemoryWalletSecrets()
        try b.create()
        alice = try WalletEngine(network: .regtest, secrets: a, store: MemoryWalletStore(), chain: chain)
        bob = try WalletEngine(network: .regtest, secrets: b, store: MemoryWalletStore(), chain: chain)
    }

    func fund(_ sats: Int64) async {
        chain.fund(alice.newReceiveAddress().string, sats)
        chain.mine()
        await alice.sync()
    }

    /// Alice zahlt Bob mit 2 sat/vB; die Zahlung hängt.
    func stuckPayment(_ amount: TransactionPlanner.Amount = .exact(50_000)) async throws -> SentPayment {
        let draft = try alice.prepare(to: bob.receiveAddress(), amount: amount, feeRate: 2)
        return try await alice.send(draft, reason: "test")
    }

    func testBumpReplacesThePaymentWithoutPayingTwice() async throws {
        await fund(200_000)
        let sent = try await stuckPayment()
        XCTAssertTrue(alice.canBump(sent.txid))
        let oldRate = try XCTUnwrap(alice.currentFeeRate(sent.txid))
        XCTAssertEqual(oldRate, 2, accuracy: 0.5)

        let draft = try alice.prepareBump(sent.txid, feeRate: 12)
        XCTAssertEqual(draft.amount, 50_000)
        XCTAssertGreaterThan(draft.newFee, sent.fee)
        XCTAssertGreaterThan(draft.newRate, draft.oldRate)
        let bumped = try await alice.bump(draft, reason: "test")
        XCTAssertNotEqual(bumped.txid, sent.txid)
        XCTAssertEqual(bumped.payment.sats, 50_000)
        XCTAssertEqual(bumped.payment.address, sent.payment.address)

        // Das Original ist aus dem Mempool, die Ersatztransaktion drin.
        XCTAssertFalse(chain.contains(sent.txid))
        XCTAssertTrue(chain.contains(bumped.txid))
        XCTAssertEqual(alice.outgoingState(sent.txid)?.state, .replaced)
        XCTAssertFalse(alice.canBump(sent.txid))
        XCTAssertEqual(alice.transactions.filter { !$0.isIncoming }.map(\.txid), [bumped.txid])

        chain.mine()
        await alice.sync()
        await bob.sync()
        XCTAssertEqual(bob.balance.confirmed, 50_000)
        XCTAssertEqual(alice.balance.total, 200_000 - 50_000 - bumped.fee)
        XCTAssertEqual(alice.outgoingState(sent.txid)?.state, .replaced)
        XCTAssertFalse(alice.canBump(bumped.txid), "bestätigt: nichts mehr zu erhöhen")
    }

    func testRateMustRise() async throws {
        await fund(200_000)
        let sent = try await stuckPayment()
        XCTAssertThrowsError(try alice.prepareBump(sent.txid, feeRate: 2)) { XCTAssertEqual($0 as? WalletFailure, .feeRateOutOfRange) }
        XCTAssertThrowsError(try alice.prepareBump(sent.txid, feeRate: 1)) { XCTAssertEqual($0 as? WalletFailure, .feeRateOutOfRange) }
    }

    func testBumpBringsAConfirmedCoinWhenThereIsNoChange() async throws {
        await fund(80_000)
        await fund(100_000)
        // Fast genau eine Münze: kein Wechselgeld, aus dem die Gebühr käme.
        let sent = try await stuckPayment(.exact(79_700))
        XCTAssertEqual(alice.outgoingState(sent.txid)?.state, .broadcast)
        let draft = try alice.prepareBump(sent.txid, feeRate: 20)
        XCTAssertEqual(draft.plan.inputs.count, 2)
        XCTAssertNotNil(draft.plan.changeIndex)
        let bumped = try await alice.bump(draft, reason: "test")
        chain.mine()
        await alice.sync()
        await bob.sync()
        XCTAssertEqual(bob.balance.confirmed, sent.payment.sats)
        XCTAssertEqual(alice.balance.total, 180_000 - sent.payment.sats - bumped.fee)
    }

    func testUncertainBumpIsSortedOutBySpender() async throws {
        await fund(200_000)
        let sent = try await stuckPayment()
        let draft = try alice.prepareBump(sent.txid, feeRate: 8)
        chain.dropBroadcastReply = true
        do {
            _ = try await alice.bump(draft, reason: "test")
            XCTFail("sollte unklar sein")
        } catch WalletFailure.broadcastUncertain(let txid) {
            XCTAssertTrue(chain.contains(txid))
            await alice.sync()
            XCTAssertEqual(alice.outgoingState(txid)?.state, .broadcast)
            XCTAssertEqual(alice.outgoingState(sent.txid)?.state, .replaced)
        }
    }

    func testPlannerFollowsBIP125() throws {
        let key = AddressPath(chain: .receive, index: 0)
        let coin = Coin(outPoint: try OutPoint(txid: String(repeating: "ab", count: 32), vout: 0), value: 100_000,
                        scriptPubKey: [0x00, 0x14] + [UInt8](repeating: 1, count: 20), path: key, confirmed: false)
        let recipient: [UInt8] = [0x00, 0x14] + [UInt8](repeating: 2, count: 20)
        let change: [UInt8] = [0x00, 0x14] + [UInt8](repeating: 3, count: 20)
        var rng = SystemRandomNumberGenerator()
        let plan = try TransactionPlanner.replacement(original: [coin], extra: [], recipient: recipient, amount: 40_000,
                                                      oldFee: 282, oldVSize: 141, feeRate: 3, changeScript: change,
                                                      changePath: AddressPath(chain: .change, index: 0), using: &rng)
        // Regel 4: mindestens alte Gebühr + 1 sat/vB auf die neue Größe.
        XCTAssertGreaterThanOrEqual(plan.fee, 282 + Int64(plan.estimatedVSize))
        XCTAssertEqual(plan.outputs[plan.recipientIndex].value, 40_000)
        XCTAssertEqual(plan.inputs.map(\.outPoint), [coin.outPoint])
        // Unbestätigte zusätzliche Münzen sind tabu.
        let unconfirmed = Coin(outPoint: try OutPoint(txid: String(repeating: "cd", count: 32), vout: 1), value: 500_000,
                               scriptPubKey: coin.scriptPubKey, path: key, confirmed: false)
        XCTAssertThrowsError(try TransactionPlanner.replacement(original: [coin], extra: [unconfirmed], recipient: recipient, amount: 99_000,
                                                                oldFee: 1000, oldVSize: 110, feeRate: 50, changeScript: change,
                                                                changePath: AddressPath(chain: .change, index: 0), using: &rng))
    }
}
