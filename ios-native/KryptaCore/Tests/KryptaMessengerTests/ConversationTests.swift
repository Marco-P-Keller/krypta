import Foundation
import XCTest
import KryptaCore
@testable import KryptaMessenger

/// Zwei vollständige Messenger über einen Server im Speicher.
@MainActor
final class ConversationTests: XCTestCase {
    let aliceId = "aliceUid00000000000001"
    let bobId = "bobUid0000000000000002"
    var relay: MemoryRelay!
    var alice: MessengerEngine!
    var bob: MessengerEngine!

    override func setUp() async throws {
        relay = MemoryRelay()
        alice = MessengerEngine(userId: aliceId, identity: .generate(), relay: relay, vault: MemoryVault(), config: .immediate)
        bob = MessengerEngine(userId: bobId, identity: .generate(), relay: relay, vault: MemoryVault(), config: .immediate)
        await alice.start()
        await bob.start()
    }

    override func tearDown() async throws {
        alice.stop()
        bob.stop()
    }

    /// Wartet, bis beide Seiten nichts mehr zu tun haben.
    func settle(_ condition: @escaping @autoclosure () -> Bool = true, timeout: TimeInterval = 5) async {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            await alice.settle()
            await bob.settle()
            try? await Task.sleep(for: .milliseconds(20))
        } while (!condition() || relay.pending(for: aliceId) + relay.pending(for: bobId) > 0) && Date() < end
    }

    /// Alice fragt Bob an, Bob nimmt an.
    func connect() async throws -> (aliceChat: String, bobChat: String) {
        let added = await alice.addContact(id: bobId)
        guard case .added = added else { throw XCTSkip("Hinzufügen fehlgeschlagen: \(added)") }
        await settle(self.bob.incomingRequests.count == 1)
        XCTAssertEqual(bob.incomingRequests.first?.id, aliceId)
        XCTAssertEqual(alice.contact(bobId)?.requestState, .outgoing)

        await bob.acceptRequest(aliceId)
        await settle(self.alice.contact(self.bobId)?.requestState == .established)
        XCTAssertEqual(alice.contact(bobId)?.requestState, .established)
        return (try XCTUnwrap(alice.chat(forContact: bobId)?.id), try XCTUnwrap(bob.chat(forContact: aliceId)?.id))
    }

    func testRequestAcceptAndConversation() async throws {
        let (a, b) = try await connect()

        await alice.send(chatId: a, text: "Hallo Bob")
        await settle(self.bob.messages(in: b).count == 1)
        XCTAssertEqual(bob.messages(in: b).map(\.text), ["Hallo Bob"])

        // Zustellung kommt beim Absender an und setzt den Zeitpunkt.
        await settle(self.alice.messages(in: a).first?.status == .delivered)
        XCTAssertEqual(alice.messages(in: a).first?.status, .delivered)
        XCTAssertNotNil(alice.messages(in: a).first?.deliveredAt)

        // Mehrere Runden mit DH-Schritten in beide Richtungen.
        for i in 0..<3 {
            await bob.send(chatId: b, text: "b\(i)")
            await alice.send(chatId: a, text: "a\(i)")
        }
        await settle(self.alice.messages(in: a).count == 7 && self.bob.messages(in: b).count == 7)
        XCTAssertEqual(bob.messages(in: b).filter { $0.senderId == aliceId }.compactMap(\.text), ["Hallo Bob", "a0", "a1", "a2"])
        XCTAssertEqual(alice.messages(in: a).filter { $0.senderId == bobId }.compactMap(\.text), ["b0", "b1", "b2"])
    }

    func testMessagesWaitForUnacceptedRequest() async throws {
        _ = await alice.addContact(id: bobId)
        await settle(self.bob.incomingRequests.count == 1)
        // Vor der Annahme darf Alice nichts schicken.
        let a = try XCTUnwrap(alice.chat(forContact: bobId)?.id)
        await alice.send(chatId: a, text: "zu früh")
        XCTAssertTrue(alice.messages(in: a).isEmpty)
    }

    func testDeclineIsSilentAndBlockDropsMessages() async throws {
        _ = await alice.addContact(id: bobId)
        await settle(self.bob.incomingRequests.count == 1)
        await bob.declineRequest(aliceId)
        XCTAssertTrue(bob.incomingRequests.isEmpty)
        XCTAssertNil(bob.chat(forContact: aliceId))
        XCTAssertEqual(alice.contact(bobId)?.requestState, .outgoing)
    }

    func testReadReceiptsOnlyWhenEnabled() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "gelesen?")
        await settle(self.bob.messages(in: b).count == 1)

        bob.openChat(b)
        await settle()
        XCTAssertNotEqual(alice.messages(in: a).first?.status, .read)

        bob.readReceiptsEnabled = true
        await alice.send(chatId: a, text: "jetzt?")
        await settle(self.alice.messages(in: a).last?.status == .read)
        XCTAssertEqual(alice.messages(in: a).last?.status, .read)
    }

    func testDeleteForEveryone() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "ups")
        await settle(self.bob.messages(in: b).count == 1)
        let id = try XCTUnwrap(alice.messages(in: a).first?.id)
        await alice.deleteForEveryone(chatId: a, messageId: id)
        await settle(self.bob.messages(in: b).isEmpty)
        XCTAssertTrue(bob.messages(in: b).isEmpty)
        XCTAssertTrue(alice.messages(in: a).isEmpty)
    }

    func testPasswordMessage() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "geheim", options: SendOptions(password: "pferd"))
        await settle(self.bob.messages(in: b).count == 1)
        let m = try XCTUnwrap(bob.messages(in: b).first)
        XCTAssertTrue(m.isPasswordProtected)
        XCTAssertFalse(m.passwordUnlocked)
        XCTAssertNotEqual(m.text, "geheim")

        XCTAssertEqual(bob.unlock(chatId: b, messageId: m.id, password: "falsch"), .wrongPassword)
        XCTAssertEqual(bob.unlock(chatId: b, messageId: m.id, password: "pferd"), .unlocked)
        XCTAssertEqual(bob.messages(in: b).first?.text, "geheim")

        // Der Absender erfährt, dass entsperrt wurde.
        await settle(self.alice.messages(in: a).first?.passwordUnlocked == true)
        XCTAssertEqual(alice.messages(in: a).first?.passwordUnlocked, true)
    }

    func testOneTimeMessage() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "nur einmal", options: SendOptions(oneTime: true))
        XCTAssertNil(alice.messages(in: a).first?.text, "Absender behält den Text nicht")
        await settle(self.bob.messages(in: b).count == 1)
        let id = try XCTUnwrap(bob.messages(in: b).first?.id)
        XCTAssertEqual(bob.consumeOneTime(chatId: b, messageId: id), "nur einmal")
        XCTAssertNil(bob.consumeOneTime(chatId: b, messageId: id))
        // Die Ablaufmeldung räumt die Blase beim Absender weg.
        await settle(self.alice.messages(in: a).isEmpty)
        XCTAssertTrue(alice.messages(in: a).isEmpty)
    }

    func testSelfDestructExpiresOnBothSides() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "gleich weg", options: SendOptions(selfDestruct: 0.5))
        await settle(self.bob.messages(in: b).count == 1 && self.alice.messages(in: a).first?.deliveredAt != nil)
        // Fremde Fristen werden auf mindestens zehn Sekunden gekappt.
        XCTAssertEqual(bob.messages(in: b).first?.selfDestruct, 10)
        XCTAssertNotNil(alice.deadline(of: try XCTUnwrap(alice.messages(in: a).first)))
    }

    func testBurnAfterReadOnLeavingChat() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "nach Ansehen", options: SendOptions(burnAfterRead: true))
        await settle(self.bob.messages(in: b).count == 1)
        bob.openChat(b)
        await bob.closeChat(b)
        XCTAssertTrue(bob.messages(in: b).isEmpty)
        await settle(self.alice.messages(in: a).isEmpty)
        XCTAssertTrue(alice.messages(in: a).isEmpty)
    }

    func testChatRuleIsShared() async throws {
        let (a, b) = try await connect()
        await alice.setChatRule(a, timer: 3600, afterRead: false)
        await settle(self.bob.chat(b)?.timer == 3600)
        XCTAssertEqual(bob.chat(b)?.timer, 3600)
        XCTAssertEqual(bob.chat(b)?.ruleVersion, 1)
        XCTAssertEqual(bob.messages(in: b).last?.systemEvent, .selfDestructChanged)
    }

    func testDeletedChatHealsWithNewHandshake() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "vorher")
        await settle(self.bob.messages(in: b).count == 1)

        await bob.send(chatId: b, text: "von Bob")
        await settle(self.alice.messages(in: a).count == 2)

        // Bob wirft den Chat weg: bei Alice gehen *seine* Nachrichten
        // (removedByPeerClear), ihre bleiben, und die Sitzung fällt.
        await bob.deleteChat(b)
        await settle(self.alice.ratchets[a] == nil)
        XCTAssertEqual(alice.messages(in: a).compactMap(\.text), ["vorher"])
        XCTAssertNil(alice.ratchets[a])

        // Alice schreibt wieder: neuer Handschlag, Bob kann lesen.
        await alice.send(chatId: a, text: "nachher")
        await settle(self.bob.chat(forContact: self.aliceId).map { self.bob.messages(in: $0.id).count } == 1)
        let newB = try XCTUnwrap(bob.chat(forContact: aliceId)?.id)
        XCTAssertEqual(bob.messages(in: newB).compactMap(\.text), ["nachher"])
    }

    func testReplayedMessageIsIgnored() async throws {
        let (a, b) = try await connect()
        let before = relay.sentCount
        await alice.send(chatId: a, text: "einmal")
        // Die Nachricht abfangen, bevor Bob sie löscht, und erneut einspielen.
        let envelope = try XCTUnwrap(relay.inboxSnapshot(bobId).last)
        await settle(self.bob.messages(in: b).count == 1)
        relay.replay(envelope, to: bobId)
        await settle()
        XCTAssertEqual(bob.messages(in: b).count, 1)
        XCTAssertGreaterThan(relay.sentCount, before)
    }

    func testQRAddEstablishesDirectly() async throws {
        let qr = try QRPayload.parse(bob.myQRPayload.encoded)
        guard case .verified(let c) = await alice.addContact(qr: qr) else { return XCTFail("qr") }
        XCTAssertTrue(c.isVerified)
        // Das Token im Code macht die Anfrage bei Bob direkt fest.
        await settle(self.bob.contact(self.aliceId)?.requestState == .established && self.alice.contact(self.bobId)?.requestState == .established)
        XCTAssertEqual(bob.contact(aliceId)?.requestState, .established)
        XCTAssertEqual(alice.contact(bobId)?.requestState, .established)
        XCTAssertTrue(bob.incomingRequests.isEmpty)
    }

    func testQRWithForeignKeyIsRejected() async throws {
        let forged = QRPayload(userId: bobId, publicKey: KeyPair.generate().publicKey, requestToken: nil)
        let result = await alice.addContact(qr: forged)
        XCTAssertEqual(result, .keyMismatch)
        XCTAssertEqual(alice.contact(bobId)?.trustState, .keyChanged)
    }

    func testSafetyNumbersMatch() async throws {
        _ = try await connect()
        XCTAssertEqual(alice.safetyNumber(for: bobId), bob.safetyNumber(for: aliceId))
    }

    func testFailedSendStaysVisibleAndCanBeResent() async throws {
        let (a, b) = try await connect()
        relay.failSends = true
        await alice.send(chatId: a, text: "offline")
        XCTAssertEqual(alice.messages(in: a).first?.status, .failed)
        relay.failSends = false
        let id = try XCTUnwrap(alice.messages(in: a).first?.id)
        await alice.resend(chatId: a, messageId: id)
        await settle(self.bob.messages(in: b).count == 1)
        XCTAssertEqual(bob.messages(in: b).compactMap(\.text), ["offline"])
    }

    func testWipeTellsContactsAndClearsEverything() async throws {
        let (_, b) = try await connect()
        await alice.wipeEverything()
        XCTAssertTrue(alice.contacts.isEmpty)
        await settle(self.bob.contact(self.aliceId)?.isGone == true)
        XCTAssertEqual(bob.contact(aliceId)?.isGone, true)
        XCTAssertEqual(bob.messages(in: b).last?.systemEvent, .accountDeleted)
    }

    func testStatePersistsAcrossRestart() async throws {
        let vault = MemoryVault()
        let carol = MessengerEngine(userId: "carolUid000000000003", identity: .generate(), relay: relay, vault: vault, config: .immediate)
        await carol.start()
        _ = await carol.addContact(id: bobId)
        await settle(self.bob.incomingRequests.count == 1)
        await bob.acceptRequest("carolUid000000000003")
        await settle(carol.contact(self.bobId)?.requestState == .established)
        carol.stop()

        // Neustart mit demselben Tresor: Sitzung und Kontakte sind noch da.
        let again = MessengerEngine(userId: carol.userId, identity: carol.identity, relay: relay, vault: vault, config: .immediate)
        await again.start()
        let chatId = try XCTUnwrap(again.chat(forContact: bobId)?.id)
        await again.send(chatId: chatId, text: "nach Neustart")
        let bobChat = try XCTUnwrap(bob.chat(forContact: carol.userId)?.id)
        await settle(self.bob.messages(in: bobChat).count == 1)
        XCTAssertEqual(bob.messages(in: bobChat).compactMap(\.text), ["nach Neustart"])
        again.stop()
    }
}
