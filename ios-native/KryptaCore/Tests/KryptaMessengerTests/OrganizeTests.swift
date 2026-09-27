import Foundation
import XCTest
import KryptaCore
@testable import KryptaMessenger

/// Stumm, angepinnt, archiviert, Suche und die Löschfrist für neue Chats.
@MainActor
final class OrganizeTests: TwoMessengers {
    /// Ein Engine mit drei Chats, ohne Netz.
    private func engineWithChats() -> (MessengerEngine, [String]) {
        let e = MessengerEngine(userId: "meUid000000000000000001", identity: .generate(), relay: MemoryRelay(), vault: MemoryVault(), config: .immediate)
        var ids: [String] = []
        for (i, name) in ["Ana", "Ben", "Cem"].enumerated() {
            let c = Contact(id: "contact\(i)000000000000001", publicKey: Data(repeating: UInt8(i + 1), count: 32), requestState: .established)
            e.contacts.append(c)
            var chat = Chat(recipientId: c.id, name: name)
            chat.lastActivity = Date(timeIntervalSince1970: TimeInterval(1000 * (i + 1)))
            e.chats.append(chat)
            ids.append(chat.id)
        }
        return (e, ids)
    }

    func testPinnedFirstArchivedApart() {
        let (e, ids) = engineWithChats()
        XCTAssertEqual(e.sortedChats.map(\.name), ["Cem", "Ben", "Ana"])

        e.setPinned(ids[0], true)
        e.setPinned(ids[1], true)
        XCTAssertEqual(e.sortedChats.map(\.name), ["Ana", "Ben", "Cem"])

        e.setArchived(ids[1], true)
        XCTAssertEqual(e.sortedChats.map(\.name), ["Ana", "Cem"])
        XCTAssertEqual(e.archivedChats.map(\.name), ["Ben"])
        // Archivieren löst die Nadel.
        XCTAssertFalse(e.chat(ids[1])!.isPinned)
        // Anpinnen holt aus dem Archiv.
        e.setPinned(ids[1], true)
        XCTAssertTrue(e.archivedChats.isEmpty)
    }

    func testPinLimit() {
        let (e, ids) = engineWithChats()
        for i in 0..<MessengerEngine.maxPinned {
            var chat = Chat(recipientId: ids[0], name: "x\(i)")
            chat.pinnedAt = Date()
            e.chats.append(chat)
        }
        XCTAssertFalse(e.setPinned(ids[2], true))
        XCTAssertFalse(e.chat(ids[2])!.isPinned)
    }

    func testMuteExpires() {
        let (e, ids) = engineWithChats()
        e.setMuted(ids[0], until: Date().addingTimeInterval(3600))
        XCTAssertTrue(e.chat(ids[0])!.isMuted())
        XCTAssertFalse(e.chat(ids[0])!.isMuted(at: Date().addingTimeInterval(7200)))
        e.setMuted(ids[0], until: nil)
        XCTAssertFalse(e.chat(ids[0])!.isMuted())
    }

    func testNewMessageBringsChatBackUnlessMuted() async throws {
        let (a, b) = try await connect()
        alice.setArchived(a, true)
        await bob.send(chatId: b, text: "Hallo?")
        await settle(self.alice.messages(in: a).count == 1)
        XCTAssertFalse(alice.chat(a)!.isArchived)

        alice.setArchived(a, true)
        alice.setMuted(a, until: .distantFuture)
        await bob.send(chatId: b, text: "Noch da?")
        await settle(self.alice.messages(in: a).count == 2)
        XCTAssertTrue(alice.chat(a)!.isArchived)
    }

    func testSearchFindsTextButNotSecrets() async throws {
        let (a, b) = try await connect()
        await alice.send(chatId: a, text: "Treffen am Café Müller")
        await alice.send(chatId: a, text: "Das Café ist zu", options: SendOptions(oneTime: true))
        await alice.send(chatId: a, text: "cafe geheim", options: SendOptions(password: "pferd"))
        await bob.send(chatId: b, text: "Welches CAFE?")
        await settle(self.bob.messages(in: b).count == 4)

        let hits = bob.searchMessages("cafe")
        XCTAssertEqual(hits.map(\.text), ["Welches CAFE?", "Treffen am Café Müller"])
        XCTAssertEqual(hits.map(\.mine), [true, false])
        XCTAssertTrue(bob.searchMessages("c").isEmpty)
    }

    func testIndexCarriesMute() async throws {
        let (a, _) = try await connect()
        let until = Date().addingTimeInterval(600)
        alice.setMuted(a, until: until)
        let entry = try XCTUnwrap(alice.notificationIndex(showNames: true).entries.first)
        XCTAssertEqual(entry.mutedUntil, until)
        let tag = try XCTUnwrap(bob.notificationTag(for: bob.contact(aliceId)!, request: false))
        XCTAssertTrue(alice.notificationIndex(showNames: true).isMuted(tag))
        XCTAssertFalse(alice.notificationIndex(showNames: true).isMuted(tag, now: until.addingTimeInterval(1)))
    }

    func testDefaultRuleForNewChats() async throws {
        alice.defaultChatRule = .timer(3600)
        XCTAssertEqual(alice.defaultChatRule, .timer(3600))
        let (a, b) = try await connect()
        await settle(self.bob.chat(b)?.timer == 3600)
        XCTAssertEqual(alice.chat(a)?.timer, 3600)
        XCTAssertEqual(bob.chat(b)?.timer, 3600)
        XCTAssertEqual(alice.chat(a)?.ruleVersion, bob.chat(b)?.ruleVersion)
    }

    func testDefaultRulesOnBothSidesConverge() async throws {
        alice.defaultChatRule = .timer(3600)
        bob.defaultChatRule = .afterRead
        let (a, b) = try await connect()
        await settle(self.alice.chat(a)?.ruleIsEphemeral == true && self.bob.chat(b)?.ruleIsEphemeral == true)
        await settle()
        let ac = try XCTUnwrap(alice.chat(a)), bc = try XCTUnwrap(bob.chat(b))
        XCTAssertEqual(ac.timer, bc.timer)
        XCTAssertEqual(ac.deleteAfterRead, bc.deleteAfterRead)
        XCTAssertEqual(ac.ruleVersion, bc.ruleVersion)
    }
}
