import Foundation
import XCTest
import KryptaCore
@testable import KryptaMessenger

/// Antworten, Reaktionen und Bearbeiten zwischen zwei Messengern.
@MainActor
final class ExtrasTests: TwoMessengers {
    func testReplyCarriesOnlyTheId() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "Kommst du morgen?")
        await settle(self.bob.messages(in: b).count == 1)
        let question = try XCTUnwrap(bob.messages(in: b).first)

        await bob.send(chatId: b, text: "Ja!", options: SendOptions(replyTo: question.id))
        await settle(self.alice.messages(in: a).count == 2)
        let answer = try XCTUnwrap(alice.messages(in: a).last)
        XCTAssertEqual(answer.text, "Ja!")
        XCTAssertEqual(answer.replyTo, question.id)
        XCTAssertEqual(bob.messages(in: b).last?.replyTo, question.id)
    }

    func testReplyToUnknownOrOneTimeIsDropped() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "einmal", options: SendOptions(oneTime: true))
        await settle(self.bob.messages(in: b).count == 1)
        let once = try XCTUnwrap(bob.messages(in: b).first)

        await bob.send(chatId: b, text: "zitiert?", options: SendOptions(replyTo: once.id))
        await bob.send(chatId: b, text: "gibt es nicht", options: SendOptions(replyTo: "0123456789abcdef"))
        await settle(self.alice.messages(in: a).count == 3)
        XCTAssertEqual(bob.messages(in: b).filter { $0.senderId == bobId }.map(\.replyTo), [nil, nil])
    }

    func testReactionRoundTripWithoutTranscriptEntry() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "Pizza?")
        await settle(self.bob.messages(in: b).count == 1)
        let pizza = try XCTUnwrap(bob.messages(in: b).first)

        let before = relay.sentCount
        await bob.react(chatId: b, messageId: pizza.id, emoji: "❤️")
        await settle(self.alice.messages(in: a).first?.reactions?[self.bobId] == "❤️")
        XCTAssertEqual(alice.messages(in: a).first?.reactions, [bobId: "❤️"])
        XCTAssertEqual(alice.messages(in: a).count, 1)
        XCTAssertEqual(bob.messages(in: b).first?.reactions, [bobId: "❤️"])
        // Keine Mitteilung: der Anhänger ist leer.
        XCTAssertEqual(relay.sentPayloads.last?.payload["nt"], .string(""))
        XCTAssertEqual(relay.sentCount, before + 1)

        await bob.react(chatId: b, messageId: pizza.id, emoji: "👍")
        await settle(self.alice.messages(in: a).first?.reactions?[self.bobId] == "👍")
        XCTAssertEqual(alice.messages(in: a).first?.reactions, [bobId: "👍"])

        await bob.react(chatId: b, messageId: pizza.id, emoji: nil)
        await settle(self.alice.messages(in: a).first?.reactions == nil)
        XCTAssertNil(alice.messages(in: a).first?.reactions)
        XCTAssertNil(bob.messages(in: b).first?.reactions)
    }

    func testNoExtrasForFlutterContacts() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "Hallo")
        await settle(self.bob.messages(in: b).count == 1)
        let hello = try XCTUnwrap(bob.messages(in: b).first)
        XCTAssertTrue(bob.supportsExtras(chatId: b))

        // Ohne `_dk` gilt die Gegenseite als Flutter-App.
        bob.updateContact(aliceId) { $0.sealedKey = nil }
        XCTAssertFalse(bob.supportsExtras(chatId: b))
        let before = relay.sentCount
        await bob.react(chatId: b, messageId: hello.id, emoji: "👍")
        await settle()
        XCTAssertEqual(relay.sentCount, before)
    }

    func testEditReplacesTextOnBothSides() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "Treffen um 8")
        await settle(self.alice.messages(in: a).first?.status == .delivered)
        let original = try XCTUnwrap(alice.messages(in: a).first)

        let ok = await alice.edit(chatId: a, messageId: original.id, text: "Treffen um 9")
        XCTAssertTrue(ok)
        await settle(self.bob.messages(in: b).first?.text == "Treffen um 9")
        XCTAssertEqual(bob.messages(in: b).map(\.text), ["Treffen um 9"])
        XCTAssertNotNil(bob.messages(in: b).first?.editedAt)
        XCTAssertEqual(alice.messages(in: a).first?.text, "Treffen um 9")
        XCTAssertNotNil(alice.messages(in: a).first?.editedAt)
    }

    func testCannotEditForeignOrProtectedMessages() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "meins")
        await alice.send(chatId: a, text: "geheim", options: SendOptions(password: "pferd"))
        await settle(self.bob.messages(in: b).count == 2)
        let mine = try XCTUnwrap(bob.messages(in: b).first)
        let secret = try XCTUnwrap(alice.messages(in: a).last)

        // Bob kann Alices Nachricht nicht bearbeiten, auch nicht mit einer
        // selbst gebauten Bearbeitung.
        let foreign = await bob.edit(chatId: b, messageId: mine.id, text: "deins")
        XCTAssertFalse(foreign)
        await bob.sendSide(chatId: b, fields: ["_ed": .string(mine.id)], content: "gefälscht")
        await settle()
        XCTAssertEqual(alice.messages(in: a).first?.text, "meins")

        let protected = await alice.edit(chatId: a, messageId: secret.id, text: "anders")
        XCTAssertFalse(protected)
    }

    func testEditWindowAndEmojiRules() {
        var m = Message(id: "m1", chatId: "c", senderId: "me", recipientId: "you", text: "x", timestamp: Date(), status: .delivered)
        XCTAssertTrue(EditPolicy.canEdit(m, me: "me"))
        XCTAssertFalse(EditPolicy.canEdit(m, me: "you"))
        XCTAssertFalse(EditPolicy.canEdit(m, me: "me", now: Date().addingTimeInterval(EditPolicy.window + 1)))
        m.status = .failed
        XCTAssertFalse(EditPolicy.canEdit(m, me: "me"))

        for ok in ["❤️", "👍", "😂", "👨‍👩‍👧‍👦", "1️⃣"] { XCTAssertTrue(ReactionPolicy.isValid(ok), ok) }
        for bad in ["", "a", "1", "👍👍", "ok", "☺"] { XCTAssertFalse(ReactionPolicy.isValid(bad), bad) }
        for quick in ReactionPolicy.quick { XCTAssertTrue(ReactionPolicy.isValid(quick), quick) }
    }
}
