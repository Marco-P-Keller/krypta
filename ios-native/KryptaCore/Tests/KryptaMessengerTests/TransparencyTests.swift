import Foundation
import XCTest
import KryptaCore
@testable import KryptaMessenger

/// Schlüsselprotokoll und Mitteilungs-Anhänger zwischen zwei Messengern.
@MainActor
final class TransparencyTests: TwoMessengers {
    func testBothPublishGenesisAndVerifyEachOther() async throws {
        _ = try await connect()
        await alice.verifyTransparency(bobId)
        await bob.verifyTransparency(aliceId)

        let published = try await relay.keyCommitments(uid: aliceId, since: nil)
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(alice.contact(bobId)?.transparencyVerified, true)
        XCTAssertEqual(bob.contact(aliceId)?.transparencyVerified, true)
        XCTAssertEqual(alice.contact(bobId)?.lastVerifiedEpoch, 0)
        XCTAssertNil(alice.transparencyChain(bobId)?.audit())
    }

    func testRestartDoesNotForkOwnChain() async throws {
        // Ein zweiter Start mit leerem Speicher übernimmt die Kette vom Server
        // statt eine zweite Epoche 0 anzulegen.
        let identity = alice.identity
        alice.stop()
        let again = MessengerEngine(userId: aliceId, identity: identity, relay: relay, vault: MemoryVault(), config: .immediate)
        await again.start()
        defer { again.stop() }
        let remote = try await relay.keyCommitments(uid: aliceId, since: nil)
        XCTAssertEqual(remote.count, 1)
        XCTAssertEqual(again.transparencyChain(aliceId)?.latestEpoch, 0)
    }

    /// Wie in Dart ist der Signaturschlüssel festgehalten: ein neuer
    /// Identitätsschlüssel kann die alte Kette nicht verlängern. Wer ihn
    /// kennenlernt, sieht einen Widerspruch statt einer stillen Übernahme.
    func testNewKeyCannotRewriteChain() async throws {
        _ = try await connect()
        await bob.verifyTransparency(aliceId)
        XCTAssertEqual(bob.contact(aliceId)?.transparencyVerified, true)

        alice.stop()
        let fresh = MessengerEngine(userId: aliceId, identity: .generate(), relay: relay, vault: MemoryVault(), config: .immediate)
        await fresh.start()
        defer { fresh.stop() }
        let remote = try await relay.keyCommitments(uid: aliceId, since: nil)
        XCTAssertEqual(remote.count, 1)

        _ = await bob.addContact(id: aliceId)
        XCTAssertEqual(bob.contact(aliceId)?.hasKeyChanged, true)
        await bob.verifyTransparency(aliceId)
        XCTAssertEqual(bob.contact(aliceId)?.transparencyVerified, false)
    }

    func testForgedCommitmentIsDetected() async throws {
        _ = try await connect()
        await alice.verifyTransparency(bobId)
        XCTAssertEqual(alice.contact(bobId)?.transparencyVerified, true)

        // Der Server schiebt Alice eine andere Epoche 1 für Bob unter —
        // signiert mit einem fremden Schlüssel.
        let mallory = KeyPair.generate()
        let head = try XCTUnwrap(alice.transparencyChain(bobId)?.head)
        let forged = try KeyCommitment.create(epoch: 1, identity: mallory, previousHash: head.commitHash)
        relay.forgeKeyCommitment(uid: bobId, epoch: 1, forged.json)
        await alice.verifyTransparency(bobId)
        XCTAssertEqual(alice.contact(bobId)?.transparencyVerified, false)
    }

    func testGossipDetectsSplitView() async throws {
        let (a, b) = try await connect()
        await alice.verifyTransparency(bobId)
        await bob.verifyTransparency(aliceId)

        // Bob hat für Alice eine andere Epoche 0 gesehen als Alice selbst.
        let fake = try KeyCommitment.create(epoch: 0, identity: alice.identity, previousHash: KeyCommitment.genesisHash, now: Date(timeIntervalSince1970: 1))
        var chain = TransparencyChain()
        XCTAssertEqual(chain.verifyAndAppend(fake, expectedPublicKey: nil), .valid)
        bob.transparency[aliceId] = chain

        await bob.send(chatId: b, text: "hallo")
        await settle(self.alice.messages(in: a).count == 1)
        XCTAssertEqual(alice.contact(bobId)?.transparencyVerified, false)
    }

    func testNotificationTags() async throws {
        let (a, _) = try await connect()
        // Anfrage: Anhänger mit dem Anfrage-Schlüssel von Bob.
        let request = try XCTUnwrap(relay.sentPayloads.first { $0.to == bobId })
        let bobIndex = bob.notificationIndex(showNames: true)
        XCTAssertEqual(bobIndex.resolve(request.payload["nt"]?.stringValue), .request)

        alice.rename(chatId: a, to: "Bob")
        bob.rename(chatId: try XCTUnwrap(bob.chat(forContact: aliceId)?.id), to: "Mami")
        let before = relay.sentPayloads.count
        await alice.send(chatId: a, text: "geheim")
        let sent = relay.sentPayloads[before...].first { $0.to == bobId }
        let tag = try XCTUnwrap(sent?.payload["nt"]?.stringValue)
        XCTAssertFalse(tag.isEmpty)
        XCTAssertFalse(tag.contains("geheim"))
        XCTAssertLessThanOrEqual(sent?.payload.count ?? 99, 10, "Firestore erlaubt höchstens zehn Felder in p")

        XCTAssertEqual(bob.notificationIndex(showNames: true).resolve(tag), .contact(name: "Mami"))
        XCTAssertEqual(bob.notificationIndex(showNames: false).resolve(tag), .contact(name: nil))
        // Ein Dritter kann den Anhänger nicht zuordnen.
        let eve = MessengerEngine(userId: "eveUid00000000000003", identity: .generate(), relay: MemoryRelay(), vault: MemoryVault())
        XCTAssertEqual(eve.notificationIndex(showNames: true).resolve(tag), .unknown)

        // Steuernachrichten (Zustellung) sind still.
        await settle()
        let controls = relay.sentPayloads[before...].filter { $0.to == aliceId }
        XCTAssertFalse(controls.isEmpty)
        XCTAssertTrue(controls.allSatisfy { $0.payload["nt"] == .string("") })

        // Blockiert: der Name fällt aus dem Index.
        bob.block(aliceId)
        XCTAssertEqual(bob.notificationIndex(showNames: true).resolve(tag), .unknown)
    }

    func testTagsAreUnlinkable() throws {
        let key = Data.random(count: 32)
        let t1 = NotificationTag.make(key: key), t2 = NotificationTag.make(key: key)
        XCTAssertNotEqual(t1, t2)
        XCTAssertTrue(NotificationTag.matches(t1, key: key))
        XCTAssertFalse(NotificationTag.matches(t1, key: Data.random(count: 32)))
        XCTAssertFalse(NotificationTag.matches("kaputt", key: key))
    }
}
