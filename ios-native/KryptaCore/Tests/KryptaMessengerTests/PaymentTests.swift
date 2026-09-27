import Foundation
import XCTest
import KryptaBitcoin
import KryptaCore
import KryptaWallet
@testable import KryptaMessenger

/// Bitcoin im Chat: zwei Messenger, zwei Wallets, eine Kette im Speicher.
@MainActor
final class PaymentTests: TwoMessengers {
    var chain: MemoryChain!
    var aliceWallet: WalletEngine!
    var bobWallet: WalletEngine!
    var aliceSecrets: MemoryWalletSecrets!

    override func setUp() async throws {
        try await super.setUp()
        chain = MemoryChain(network: .regtest)
        aliceSecrets = MemoryWalletSecrets()
        try aliceSecrets.create()
        let bobSecrets = MemoryWalletSecrets()
        try bobSecrets.create()
        aliceWallet = try WalletEngine(network: .regtest, secrets: aliceSecrets, store: MemoryVault(), chain: chain)
        bobWallet = try WalletEngine(network: .regtest, secrets: bobSecrets, store: MemoryVault(), chain: chain)
        alice.attach(wallet: aliceWallet)
        bob.attach(wallet: bobWallet)
    }

    /// Verbinden und je eine Nachricht hin und her: danach kennt jede Seite
    /// die Adresse der anderen.
    func connectWithWallets() async throws -> (a: String, b: String) {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "Hi")
        await settle(self.bob.messages(in: b).count == 1)
        await bob.send(chatId: b, text: "Hallo")
        await settle(self.alice.contact(self.bobId)?.bitcoinAddress != nil)
        await alice.send(chatId: a, text: "Na?")
        await settle(self.bob.contact(self.aliceId)?.bitcoinAddress != nil)
        return (a, b)
    }

    func testAddressesAreExchangedInsideEncryption() async throws {
        _ = try await connectWithWallets()
        let bobAddress = try XCTUnwrap(alice.contact(bobId)?.bitcoinAddress)
        XCTAssertEqual(bobAddress, bobWallet.chatAddress(for: aliceId))
        XCTAssertEqual(alice.contact(bobId)?.acceptsBitcoin, true)
        XCTAssertEqual(alice.contact(bobId)?.bitcoinNetwork, "regtest")
        XCTAssertNil(alice.paymentBlock(for: bobId))
        XCTAssertEqual(alice.paymentAddress(for: bobId)?.string, bobAddress)

        // Der Server sieht keine Adresse und keine Spur von Bitcoin.
        for (_, payload) in relay.sentPayloads {
            let text = try payload.jsonString()
            XCTAssertFalse(text.contains(bobAddress))
            XCTAssertFalse(text.contains("_btc"))
            XCTAssertFalse(text.contains("bcrt1"))
        }
    }

    /// Der ganze Weg: bezahlen, Nachricht, Prüfung beim Empfänger, Block.
    func testPayInChat() async throws {
        let (a, b) = try await connectWithWallets()
        chain.fund(aliceWallet.receiveAddress().string, 500_000)
        chain.mine()
        await aliceWallet.sync()

        let bobAddress = try XCTUnwrap(alice.paymentAddress(for: bobId))
        let draft = try aliceWallet.prepare(to: bobAddress, amount: .exact(120_000), feeLevel: .normal, contactId: bobId, note: "Für das Konzert")
        let sent = try await alice.pay(chatId: a, draft: draft, reason: "test")
        XCTAssertTrue(chain.contains(sent.txid))

        await settle(self.bob.messages(in: b).last?.payment != nil)
        let message = try XCTUnwrap(bob.messages(in: b).last)
        XCTAssertEqual(message.payment?.txid, sent.txid)
        XCTAssertEqual(message.text, "Für das Konzert")
        XCTAssertEqual(alice.messages(in: a).last?.payment, sent.payment)

        // Bob glaubt der Nachricht nicht, er prüft.
        await settle(self.bobWallet.claimStatus(messageId: message.id) != .checking)
        XCTAssertEqual(bobWallet.claimStatus(messageId: message.id), .unconfirmed(received: 120_000))
        chain.mine()
        await bobWallet.sync()
        guard case .confirmed(120_000, _, true)? = bobWallet.claimStatus(messageId: message.id) else {
            return XCTFail("\(String(describing: bobWallet.claimStatus(messageId: message.id)))")
        }
        XCTAssertEqual(bobWallet.balance.confirmed, 120_000)

        // Bobs Adresse ist benutzt; mit seiner nächsten Nachricht kommt eine neue.
        await bob.send(chatId: b, text: "Danke!")
        await settle(self.alice.contact(self.bobId)?.bitcoinAddress != bobAddress.string)
        XCTAssertNotEqual(alice.contact(bobId)?.bitcoinAddress, bobAddress.string)
    }

    /// Gebühr erhöht: Bob bekommt die neue Transaktion verschlüsselt
    /// nachgereicht und prüft sie wie jede Zahlung.
    func testFeeBumpUpdatesThePaymentInChat() async throws {
        let (a, b) = try await connectWithWallets()
        chain.fund(aliceWallet.receiveAddress().string, 400_000)
        chain.mine()
        await aliceWallet.sync()
        let draft = try aliceWallet.prepare(to: XCTUnwrap(alice.paymentAddress(for: bobId)), amount: .exact(70_000), feeRate: 2, contactId: bobId)
        let sent = try await alice.pay(chatId: a, draft: draft, reason: "test")
        await settle(self.bob.messages(in: b).last?.payment != nil)
        let message = try XCTUnwrap(bob.messages(in: b).last)
        await settle(self.bobWallet.claimStatus(messageId: message.id) == .unconfirmed(received: 70_000))

        let bump = try aliceWallet.prepareBump(sent.txid, feeRate: 15)
        let bumped = try await alice.bumpFee(bump, reason: "test")
        XCTAssertEqual(alice.messages(in: a).last?.payment?.txid, bumped.txid)
        await settle(self.bob.messages(in: b).last?.payment?.txid == bumped.txid)
        XCTAssertEqual(bob.messages(in: b).last?.payment?.txid, bumped.txid)
        XCTAssertEqual(bob.messages(in: b).filter { $0.payment != nil }.count, 1)

        chain.mine()
        await bobWallet.sync()
        guard case .confirmed(70_000, _, true)? = bobWallet.claimStatus(messageId: message.id) else {
            return XCTFail("\(String(describing: bobWallet.claimStatus(messageId: message.id)))")
        }
    }

    /// Eine Umleitung auf eine andere Zahlung (anderer Betrag) nimmt Bob nicht an.
    func testPaymentUpdateMustKeepAmountAndAddress() async throws {
        let (a, b) = try await connectWithWallets()
        chain.fund(aliceWallet.receiveAddress().string, 400_000)
        chain.mine()
        await aliceWallet.sync()
        let draft = try aliceWallet.prepare(to: XCTUnwrap(alice.paymentAddress(for: bobId)), amount: .exact(60_000), feeRate: 2, contactId: bobId)
        let sent = try await alice.pay(chatId: a, draft: draft, reason: "test")
        await settle(self.bob.messages(in: b).last?.payment != nil)
        let message = try XCTUnwrap(bob.messages(in: b).last)
        var forged = sent.payment.json.objectValue!
        forged["txid"] = .string(String(repeating: "ee", count: 32))
        forged["sat"] = 90_000
        await alice.sendSide(chatId: a, fields: ["_payu": .object(["m": .string(message.id), "p": .object(forged)])])
        await settle()
        XCTAssertEqual(bob.messages(in: b).last?.payment?.txid, sent.txid)
    }

    /// Scheitert nur die Nachricht, schickt „erneut senden" nur sie — nie
    /// eine zweite Transaktion.
    func testResendPaymentMessageNeverPaysTwice() async throws {
        let (a, b) = try await connectWithWallets()
        chain.fund(aliceWallet.receiveAddress().string, 300_000)
        chain.mine()
        await aliceWallet.sync()
        let draft = try aliceWallet.prepare(to: XCTUnwrap(alice.paymentAddress(for: bobId)), amount: .exact(50_000), feeRate: 2, contactId: bobId)
        relay.failSends = true
        let sent = try await alice.pay(chatId: a, draft: draft, reason: "test")
        let failed = try XCTUnwrap(alice.messages(in: a).last)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(chain.broadcasts, 1)

        relay.failSends = false
        await alice.resend(chatId: a, messageId: failed.id)
        await settle(self.bob.messages(in: b).last?.payment != nil)
        XCTAssertEqual(bob.messages(in: b).last?.payment?.txid, sent.txid)
        XCTAssertEqual(chain.broadcasts, 1, "keine zweite Transaktion")
        XCTAssertEqual(alice.messages(in: a).filter { $0.payment != nil }.count, 1)
    }

    /// Wer keine Wallet hat (Flutter, oder ausgeschaltet), bekommt keine
    /// Adresse und kann nicht bezahlt werden.
    func testNoWalletMeansNoAddress() async throws {
        bob.attach(wallet: nil)
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "Hi")
        await settle(self.bob.messages(in: b).count == 1)
        await bob.send(chatId: b, text: "Hallo")
        await settle(self.alice.contact(self.bobId)?.acceptsBitcoin == false)
        XCTAssertEqual(alice.paymentBlock(for: bobId), .noWalletThere)
        XCTAssertNil(alice.paymentAddress(for: bobId))
        // Alice hat Bob nie eine Adresse gegeben.
        XCTAssertNil(bob.contact(aliceId)?.bitcoinAddress)

        // Schaltet Alice Zahlungen im Chat aus, vergisst Bob ihre Adresse.
        bob.attach(wallet: bobWallet)
        await bob.send(chatId: b, text: "jetzt mit Wallet")
        await settle(self.alice.contact(self.bobId)?.acceptsBitcoin == true)
        await alice.send(chatId: a, text: "gut")
        await settle(self.bob.contact(self.aliceId)?.bitcoinAddress != nil)
        aliceWallet.chatPaymentsEnabled = false
        await alice.send(chatId: a, text: "und aus")
        await settle(self.bob.contact(self.aliceId)?.bitcoinAddress == nil)
        XCTAssertEqual(bob.paymentBlock(for: aliceId), .noWalletThere)
    }

    /// Eine erfundene Zahlung im Chat wird nie als Geld angezeigt.
    func testForgedPaymentMessageIsNotBelieved() async throws {
        let (a, b) = try await connectWithWallets()
        let bobAddress = try XCTUnwrap(alice.contact(bobId)?.bitcoinAddress)
        let fake = ChatPayment(txid: String(repeating: "cd", count: 32), vout: 0, sats: 21_000_000, address: bobAddress, network: .regtest)
        await alice.sendPaymentMessage(chatId: a, payment: fake, note: "Reich!")
        await settle(self.bob.messages(in: b).last?.payment != nil)
        let message = try XCTUnwrap(bob.messages(in: b).last)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(bobWallet.claimStatus(messageId: message.id), .checking)
        XCTAssertEqual(bobWallet.balance.total, 0)
    }
}
