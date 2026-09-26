import Foundation
import XCTest
import KryptaCore
@testable import KryptaMessenger

/// Sealed Sender zwischen zwei nativen Messengern: was der Server sieht und
/// was passiert, wenn er nicht mitspielt.
@MainActor
final class SealedSenderTests: TwoMessengers {
    func testMessagesAfterConnectAreSealed() async throws {
        let (a, b) = try await connect()
        await settle()
        XCTAssertNotNil(alice.contact(bobId)?.sealedKey, "Bob hat seinen Zustellschlüssel mit der Annahme geschickt")
        XCTAssertNotNil(bob.contact(aliceId)?.sealedKey, "Alice hat ihren mit der Anfrage geschickt")

        let before = relay.sealedCount
        relay.failInboxDeletes = [bobId]
        await alice.send(chatId: a, text: "ohne Absender")
        XCTAssertGreaterThan(relay.sealedCount, before)

        // Was auf dem Server liegt: kein Absender, keine Kennung, kein Ratchet-Feld.
        let stored = try XCTUnwrap(relay.inboxSnapshot(bobId).last)
        XCTAssertEqual(stored.senderId, "")
        XCTAssertEqual(stored.messageId, "")
        XCTAssertNotNil(stored.sealed)
        let seen = try XCTUnwrap(relay.sentPayloads.last { $0.to == bobId }?.payload)
        XCTAssertEqual(Set(seen.keys).subtracting(["nt"]), ["s"])

        await settle(self.bob.messages(in: b).count == 1)
        XCTAssertEqual(bob.messages(in: b).map(\.text), ["ohne Absender"])
        // Die eigene Kopie räumt der Absender auch versiegelt weg.
        await settle(self.alice.messages(in: a).first?.status == .delivered)
        XCTAssertEqual(relay.pending(for: bobId), 0)
    }

    func testFallsBackWhenServerRejectsSealed() async throws {
        let (a, b) = try await connect()
        await settle()
        relay.rejectSealed = true
        let before = relay.sealedCount
        await alice.send(chatId: a, text: "trotzdem da")
        await settle(self.bob.messages(in: b).count == 1)
        XCTAssertEqual(bob.messages(in: b).map(\.text), ["trotzdem da"])
        XCTAssertEqual(relay.sealedCount, before)
        XCTAssertTrue(alice.sealedPaused(bobId), "nach einer Ablehnung eine Weile nicht erneut versuchen")
    }

    func testNetworkErrorDoesNotRevealSender() async throws {
        let (a, _) = try await connect()
        await settle()
        let before = relay.sentPayloads.count
        relay.failSends = true
        await alice.send(chatId: a, text: "offline")
        relay.failSends = false
        XCTAssertEqual(alice.messages(in: a).first?.status, .failed)
        XCTAssertEqual(relay.sentPayloads.count, before, "kein Rückfall auf den Weg mit Absender")
    }

    func testBlockingRotatesTheAccessKey() async throws {
        let (a, b) = try await connect()
        await settle()
        let oldKey = try XCTUnwrap(bob.meta.sealedAccessKey)
        bob.block(aliceId)
        XCTAssertNotEqual(bob.meta.sealedAccessKey, oldKey)
        await settle()

        // Alice kennt nur den alten Schlüssel: der Server weist sie ab.
        let before = relay.sealedCount
        await alice.send(chatId: a, text: "gesperrt")
        await settle()
        XCTAssertEqual(relay.sealedCount, before)
        XCTAssertTrue(bob.messages(in: b).isEmpty)
    }

    func testRequestFromQRCodeIsAlreadySealed() async throws {
        let qr = try QRPayload.parse(bob.myQRPayload.encoded)
        XCTAssertNotNil(qr.accessKey)
        guard case .verified = await alice.addContact(qr: qr) else { return XCTFail("qr") }
        XCTAssertEqual(relay.sealedCount, 1, "auch die Anfrage verrät nicht, wer sich verbindet")
        await settle(self.bob.contact(self.aliceId)?.requestState == .established && self.alice.contact(self.bobId)?.requestState == .established)
        XCTAssertEqual(bob.contact(aliceId)?.requestState, .established)
    }

    func testQRAccessKeyMustBeWellFormed() throws {
        var map = try JSONObject.parse(bob.myQRPayload.encoded)
        map["dk"] = "kurz"
        XCTAssertThrowsError(try QRPayload.parse(map.jsonString())) { XCTAssertEqual($0 as? QRPayload.ParseError, .invalidFormat) }
        map.removeValue(forKey: "dk")
        XCTAssertNil(try QRPayload.parse(map.jsonString()).accessKey, "Codes der Flutter-Fassung haben kein dk")
    }

    func testForeignSealedEnvelopeIsDropped() async throws {
        let (_, b) = try await connect()
        await settle()
        // Jemand legt Bob einen Umschlag hin, der für jemand anderen war.
        let eve = KeyPair.generate()
        let blob = try SealedSender.seal(
            .init(senderId: aliceId, messageId: UUID().uuidString.lowercased(), payload: ["v": 3]),
            recipientId: bobId, recipientIdentity: eve.publicKey
        )
        relay.replay(InboxEnvelope(docId: "x", senderId: "", messageId: "", payload: [:], sealed: blob), to: bobId)
        await settle()
        XCTAssertTrue(bob.messages(in: b).isEmpty)
        XCTAssertEqual(relay.pending(for: bobId), 0, "auch Unlesbares wird vom Server geräumt")
    }

    // MARK: - Post-Quanten (iOS 26 / macOS 26)

    func testSessionsArePostQuantumAndDowngradeIsRefused() async throws {
        try XCTSkipUnless(PostQuantum.isAvailable, "ML-KEM braucht iOS 26 / macOS 26")
        let (a, b) = try await connect()
        await settle()
        XCTAssertEqual(alice.contact(bobId)?.postQuantum, true)
        XCTAssertEqual(bob.contact(aliceId)?.postQuantum, true)

        // Der Server liefert Bobs Bündel ohne ML-KEM aus und Alice braucht
        // eine neue Sitzung: lieber keine Nachricht als eine schwächere.
        let published = try await relay.preKeyBundle(uid: bobId)
        var stripped = try XCTUnwrap(published)
        stripped.removeValue(forKey: "pqpk")
        stripped.removeValue(forKey: "pqs")
        try await relay.publishPreKeyBundle(uid: bobId, bundle: stripped)
        alice.discardSession(chatId: a)
        await alice.send(chatId: a, text: "herabgestuft?")
        XCTAssertEqual(alice.messages(in: a).last?.status, .failed)
        await settle()
        XCTAssertTrue(bob.messages(in: b).isEmpty)
    }
}
