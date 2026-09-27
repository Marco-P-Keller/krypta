import Foundation
import XCTest
import KryptaCore
@testable import KryptaMessenger

/// Drei Messenger: Alice kennt Bob und Carol, die beiden kennen sich nicht.
@MainActor
final class GroupTests: XCTestCase {
    let aliceId = "aliceUid00000000000001"
    let bobId = "bobUid0000000000000002"
    let carolId = "carolUid00000000000003"
    var relay: MemoryRelay!
    var blobs: MemoryBlobStore!
    var alice: MessengerEngine!
    var bob: MessengerEngine!
    var carol: MessengerEngine!
    var all: [MessengerEngine] { [alice, bob, carol] }

    override func setUp() async throws {
        relay = MemoryRelay()
        blobs = MemoryBlobStore()
        func make(_ id: String) -> MessengerEngine {
            MessengerEngine(userId: id, identity: .generate(), relay: relay, vault: MemoryVault(), blobs: blobs, config: .immediate)
        }
        alice = make(aliceId)
        bob = make(bobId)
        carol = make(carolId)
        for e in all { await e.start() }
        try await connect(alice, bob)
        try await connect(alice, carol)
    }

    override func tearDown() async throws {
        for e in all { e.stop() }
    }

    func settle(_ condition: @escaping @autoclosure () -> Bool = true, timeout: TimeInterval = 5) async {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for e in all { await e.settle() }
            try? await Task.sleep(for: .milliseconds(20))
        } while (!condition() || [aliceId, bobId, carolId].map { relay.pending(for: $0) }.reduce(0, +) > 0) && Date() < end
    }

    func connect(_ a: MessengerEngine, _ b: MessengerEngine) async throws {
        guard case .added = await a.addContact(id: b.userId) else { throw XCTSkip("Hinzufügen fehlgeschlagen") }
        await settle(b.incomingRequests.contains { $0.id == a.userId })
        await b.acceptRequest(a.userId)
        await settle(a.contact(b.userId)?.requestState == .established)
        // Einmal hin und her, damit beide den Zustellschlüssel (_dk) kennen.
        let ab = try XCTUnwrap(a.chat(forContact: b.userId)?.id)
        await a.send(chatId: ab, text: "hi")
        await settle(b.chat(forContact: a.userId).map { b.messages(in: $0.id).count == 1 } ?? false)
    }

    func groupChat(_ e: MessengerEngine) -> Chat? { e.chats.first { $0.isGroup } }

    /// Alice legt „Wandern" mit Bob und Carol an.
    func makeGroup() async throws -> (a: String, b: String, c: String) {
        let created = await alice.createGroup(name: "Wandern", memberIds: [bobId, carolId])
        let a = try XCTUnwrap(created)
        await settle(self.groupChat(self.bob) != nil && self.groupChat(self.carol) != nil)
        return (a, try XCTUnwrap(groupChat(bob)?.id), try XCTUnwrap(groupChat(carol)?.id))
    }

    func texts(_ e: MessengerEngine, _ chatId: String) -> [String] {
        e.messages(in: chatId).filter { !$0.isSystemEvent }.compactMap(\.text)
    }

    // MARK: -

    func testCreateIntroducesMembersAndMessagesReachEveryone() async throws {
        let (a, b, c) = try await makeGroup()
        XCTAssertEqual(groupChat(bob)?.name, "Wandern")
        XCTAssertEqual(Set(groupChat(carol)?.group?.members ?? []), [aliceId, bobId, carolId])
        XCTAssertEqual(groupChat(carol)?.group?.admin, aliceId)

        // Bob und Carol kennen sich jetzt, vorgestellt von Alice, unbestätigt,
        // und ihr Einzelchat steht nicht in der Liste.
        let carolAtBob = try XCTUnwrap(bob.contact(carolId))
        XCTAssertEqual(carolAtBob.introducedBy, aliceId)
        XCTAssertEqual(carolAtBob.requestState, .established)
        XCTAssertEqual(carolAtBob.trustState, .unverified)
        XCTAssertFalse(bob.sortedChats.contains { $0.recipientId == carolId })

        await alice.send(chatId: a, text: "Samstag 9 Uhr?")
        await settle(self.texts(self.bob, b).count == 1 && self.texts(self.carol, c).count == 1)
        XCTAssertEqual(texts(bob, b), ["Samstag 9 Uhr?"])
        XCTAssertEqual(texts(carol, c), ["Samstag 9 Uhr?"])
        XCTAssertEqual(bob.messages(in: b).last?.senderId, aliceId)

        // Bob antwortet: Carol bekommt es über die Sitzung, die es vorher nicht gab.
        await bob.send(chatId: b, text: "Bin dabei")
        await settle(self.texts(self.carol, c).count == 2 && self.texts(self.alice, a).count == 2)
        XCTAssertEqual(texts(carol, c), ["Samstag 9 Uhr?", "Bin dabei"])
        XCTAssertEqual(carol.messages(in: c).last?.senderId, bobId)
        XCTAssertEqual(texts(alice, a), ["Samstag 9 Uhr?", "Bin dabei"])

        // Zugestellt, und nichts bleibt auf dem Server.
        await settle(self.alice.messages(in: a).first { !$0.isSystemEvent }?.status == .delivered)
        XCTAssertEqual(alice.messages(in: a).first { !$0.isSystemEvent }?.status, .delivered)
        XCTAssertEqual(relay.pending(for: bobId) + relay.pending(for: carolId), 0)
        // Der Einzelchat Bob–Carol bleibt verborgen, solange sie nicht direkt schreiben.
        XCTAssertFalse(carol.sortedChats.contains { $0.recipientId == bobId })
    }

    func testGroupMessagesUseTheGroupTag() async throws {
        let (a, _, _) = try await makeGroup()
        await alice.send(chatId: a, text: "Tag?")
        await settle()
        let sent = relay.sentPayloads.filter { $0.to == bobId }.last?.payload
        let tag = sent?["nt"]?.stringValue
        let index = bob.notificationIndex(showNames: true)
        XCTAssertEqual(index.resolve(tag), .contact(name: "Wandern", id: groupChat(bob)!.recipientId))
        XCTAssertEqual(bob.chat(forContact: groupChat(bob)!.recipientId)?.id, groupChat(bob)?.id)
    }

    func testOnlyTheAdminChangesTheGroup() async throws {
        let (a, b, c) = try await makeGroup()
        // Bob schickt einen gefälschten Stand mit höherer Version.
        let g = try XCTUnwrap(groupChat(bob)?.group)
        var map = try XCTUnwrap(bob.groupPayload(g, chat: groupChat(bob)!).objectValue)
        map["n"] = "Gekapert"
        map["v"] = .int(99)
        map["a"] = .string(bobId)
        await bob.fanOut(chatId: b, members: [aliceId, carolId], messageId: UUID().uuidString.lowercased(), quiet: true) { _ in ("", ["_grp": .object(map)]) }
        await settle()
        XCTAssertEqual(groupChat(alice)?.name, "Wandern")
        XCTAssertEqual(groupChat(carol)?.name, "Wandern")

        await alice.renameGroup(a, to: "Bergtour")
        await settle(self.groupChat(self.bob)?.name == "Bergtour" && self.groupChat(self.carol)?.name == "Bergtour")
        XCTAssertEqual(groupChat(bob)?.group?.version, 2)
        XCTAssertEqual(carol.messages(in: c).last?.systemEvent, .groupRenamed)
        XCTAssertEqual(carol.messages(in: c).last?.text, "Bergtour")
    }

    func testRemovedMemberIsOut() async throws {
        let (a, b, c) = try await makeGroup()
        await alice.removeMember(a, carolId)
        await settle(self.groupChat(self.carol)?.group?.hasLeft == true && self.groupChat(self.bob)?.group?.members.count == 2)
        XCTAssertTrue(try XCTUnwrap(groupChat(carol)?.group).hasLeft)
        XCTAssertEqual(carol.messages(in: c).last?.systemEvent, .groupRemovedYou)
        XCTAssertFalse(carol.canWrite(chatId: c))

        // Was Carol noch in die Gruppe schickt (alte App, gefälscht), kommt nicht an.
        let stale = try XCTUnwrap(groupChat(carol)?.group)
        await carol.fanOut(chatId: c, members: [aliceId, bobId], messageId: UUID().uuidString.lowercased(), quiet: false) { _ in
            ("Ich bin noch da", ["_g": .string(stale.id)])
        }
        await settle()
        XCTAssertFalse(texts(bob, b).contains("Ich bin noch da"))
        XCTAssertFalse(texts(alice, a).contains("Ich bin noch da"))
    }

    func testAddMember() async throws {
        let dave = MessengerEngine(userId: "daveUid000000000000004", identity: .generate(), relay: relay, vault: MemoryVault(), config: .immediate)
        await dave.start()
        defer { dave.stop() }
        try await connect(alice, dave)
        let (a, b, _) = try await makeGroup()

        await alice.addMembers(a, [dave.userId])
        await settle(dave.chats.contains { $0.isGroup } && self.groupChat(self.bob)?.group?.members.count == 4)
        let d = try XCTUnwrap(dave.chats.first { $0.isGroup }?.id)
        XCTAssertEqual(bob.messages(in: b).last?.systemEvent, .groupMemberAdded)
        XCTAssertEqual(bob.messages(in: b).last?.text, dave.userId)

        await dave.send(chatId: d, text: "Hallo zusammen")
        await settle(self.texts(self.bob, b).contains("Hallo zusammen"))
        XCTAssertTrue(texts(bob, b).contains("Hallo zusammen"))
        await dave.settle()
    }

    func testAdminLeavesAndTheSmallestIdTakesOver() async throws {
        let (a, b, c) = try await makeGroup()
        await alice.leaveGroup(a)
        await settle(self.groupChat(self.bob)?.group?.members.count == 2 && self.groupChat(self.carol)?.group?.members.count == 2)
        XCTAssertTrue(try XCTUnwrap(groupChat(alice)?.group).hasLeft)
        XCTAssertFalse(alice.canWrite(chatId: a))
        let successor = [bobId, carolId].min { $0.utf16.lexicographicallyPrecedes($1.utf16) }!
        XCTAssertEqual(groupChat(bob)?.group?.admin, successor)
        XCTAssertEqual(groupChat(carol)?.group?.admin, successor)

        // Der Nachfolger kann umbenennen, der andere nicht.
        let (heir, heirChat) = successor == bobId ? (bob!, b) : (carol!, c)
        await heir.renameGroup(heirChat, to: "Ohne Alice")
        await settle(self.groupChat(self.bob)?.name == "Ohne Alice" && self.groupChat(self.carol)?.name == "Ohne Alice")
        XCTAssertEqual(groupChat(bob)?.name, "Ohne Alice")
        // Alice bekommt nichts mehr.
        XCTAssertEqual(groupChat(alice)?.name, "Wandern")
    }

    func testReactionsAndEditsInGroups() async throws {
        let (a, b, c) = try await makeGroup()
        await alice.send(chatId: a, text: "Treffpunkt Bahnhof")
        await settle(self.texts(self.carol, c).count == 1 && self.texts(self.bob, b).count == 1)
        let msg = try XCTUnwrap(carol.messages(in: c).last)

        await carol.react(chatId: c, messageId: msg.id, emoji: "👍")
        await settle(self.alice.messages(in: a).last?.reactions?[self.carolId] == "👍" && self.bob.messages(in: b).last?.reactions?[self.carolId] == "👍")
        XCTAssertEqual(bob.messages(in: b).last?.reactions, [carolId: "👍"])

        await alice.edit(chatId: a, messageId: msg.id, text: "Treffpunkt Parkplatz")
        await settle(self.texts(self.bob, b) == ["Treffpunkt Parkplatz"] && self.texts(self.carol, c) == ["Treffpunkt Parkplatz"])
        XCTAssertEqual(texts(carol, c), ["Treffpunkt Parkplatz"])

        // Bob kann Alices Nachricht nicht für alle löschen, Alice schon.
        await bob.deleteForEveryone(chatId: b, messageId: msg.id)
        await settle()
        XCTAssertEqual(texts(carol, c), ["Treffpunkt Parkplatz"])
        await alice.deleteForEveryone(chatId: a, messageId: msg.id)
        await settle(self.texts(self.carol, c).isEmpty && self.texts(self.bob, b).isEmpty)
        XCTAssertTrue(texts(carol, c).isEmpty)
    }

    func testPasswordMessageInGroupOpensForEachMember() async throws {
        let (a, b, c) = try await makeGroup()
        await alice.send(chatId: a, text: "Tresor: 1234", options: SendOptions(password: "berg"))
        await settle(self.bob.messages(in: b).contains { $0.isPasswordProtected } && self.carol.messages(in: c).contains { $0.isPasswordProtected })
        for (e, chat) in [(bob!, b), (carol!, c)] {
            let m = try XCTUnwrap(e.messages(in: chat).last)
            XCTAssertEqual(e.unlock(chatId: chat, messageId: m.id, password: "berg"), .unlocked)
            XCTAssertEqual(e.messages(in: chat).last?.text, "Tresor: 1234")
        }
    }

    func testIntroductionNeedsTheServerKey() async throws {
        // Alice (oder ein Server dazwischen) kündigt für Carol einen falschen Schlüssel an.
        let aliceAtBob = try XCTUnwrap(bob.contact(aliceId))
        let fake = KeyPair.generate().publicKey
        let map: JSONObject = [
            "id": .string(String(repeating: "ab", count: 16)), "n": "Falle", "v": 1, "a": .string(aliceId),
            "s": .string(Data.random(count: 32).base64),
            "m": .array([
                .object(["u": .string(aliceId), "k": .string(aliceAtBob.publicKey.base64)]),
                .object(["u": .string(bobId), "k": .string(bob.identity.publicKey.base64)]),
                .object(["u": .string(carolId), "k": .string(fake.base64)]),
            ]),
        ]
        await bob.applyGroupUpdate(from: aliceAtBob, map: map)
        XCTAssertNotNil(groupChat(bob))
        XCTAssertNil(bob.contact(carolId))
    }

    func testStrangersCannotInviteAndLeftGroupsStayLeft() async throws {
        let (a, b, _) = try await makeGroup()
        // Carol ist bei Bob nur vorgestellt: eine neue Gruppe von ihr nimmt er an
        // (angenommener Kontakt). Eine Einladung zu einer Gruppe, die Bob
        // verlassen hat, nicht.
        await bob.leaveGroup(b)
        await settle(self.groupChat(self.alice)?.group?.members.count == 2)
        let old = try XCTUnwrap(groupChat(alice)?.group)
        var map = try XCTUnwrap(alice.groupPayload(old, chat: groupChat(alice)!).objectValue)
        map["v"] = .int(old.version + 5)
        map["m"] = .array(([aliceId, bobId, carolId]).map { uid in
            .object(["u": .string(uid), "k": .string((uid == aliceId ? alice.identity.publicKey : alice.contact(uid)!.publicKey).base64)])
        })
        await bob.deleteChat(b, announce: false)
        XCTAssertNil(groupChat(bob))
        await bob.applyGroupUpdate(from: bob.contact(aliceId)!, map: map)
        XCTAssertNil(groupChat(bob))
        _ = a
    }

    func testAttachmentInGroupLeavesTheServerWhenEveryoneHasIt() async throws {
        let (a, b, c) = try await makeGroup()
        let data = Data.random(count: 20_000)
        await alice.sendAttachment(chatId: a, OutgoingAttachment(data: data, kind: .file, mime: "application/pdf", name: "Route.pdf"), caption: "Karte")
        func ready(_ e: MessengerEngine, _ chat: String) -> Bool { e.messages(in: chat).last?.attachment?.state == .ready }
        await settle(ready(self.bob, b) && ready(self.carol, c) && self.blobs.storedIds.isEmpty)
        XCTAssertEqual(bob.attachmentData(try XCTUnwrap(bob.messages(in: b).last)), data)
        XCTAssertEqual(carol.messages(in: c).last?.attachment?.name, "Route.pdf")
        XCTAssertEqual(carol.messages(in: c).last?.text, "Karte")
        XCTAssertTrue(blobs.storedIds.isEmpty)
    }

    func testBurnAfterReadReachesTheSender() async throws {
        let (a, b, _) = try await makeGroup()
        await alice.send(chatId: a, text: "weg damit", options: SendOptions(burnAfterRead: true))
        await settle(self.texts(self.bob, b).count == 1)
        bob.openChat(b)
        await bob.closeChat(b)
        await settle(self.texts(self.alice, a).isEmpty)
        XCTAssertTrue(texts(alice, a).isEmpty)
        XCTAssertTrue(texts(bob, b).isEmpty)
    }
}
