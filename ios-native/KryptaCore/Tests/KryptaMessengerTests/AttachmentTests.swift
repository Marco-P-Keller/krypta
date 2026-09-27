import Foundation
import XCTest
import KryptaCore
@testable import KryptaMessenger

/// Anhänge zwischen zwei Messengern, mit einem Blob-Speicher im Speicher.
@MainActor
final class AttachmentTests: TwoMessengers {
    var blobs: MemoryBlobStore!
    var aliceVault: MemoryVault!
    var bobVault: MemoryVault!

    override func setUp() async throws {
        relay = MemoryRelay()
        blobs = MemoryBlobStore()
        aliceVault = MemoryVault()
        bobVault = MemoryVault()
        alice = MessengerEngine(userId: aliceId, identity: .generate(), relay: relay, vault: aliceVault, blobs: blobs, config: .immediate)
        bob = MessengerEngine(userId: bobId, identity: .generate(), relay: relay, vault: bobVault, blobs: blobs, config: .immediate)
        await alice.start()
        await bob.start()
    }

    func photo(_ size: Int = 50_000) -> OutgoingAttachment {
        OutgoingAttachment(data: Data.random(count: size), kind: .image, mime: "image/jpeg", width: 800, height: 600,
                           thumbnail: Data(repeating: 7, count: 300))
    }

    func received(_ chat: String) -> Message? { bob.messages(in: chat).last { $0.attachment != nil } }

    // MARK: - Krypto

    func testCryptoRoundTripAndPadding() throws {
        let data = Data.random(count: 10_000)
        let sealed = try AttachmentCrypto.seal(data)
        XCTAssertEqual(try AttachmentCrypto.open(sealed.blob, key: sealed.key, digest: sealed.digest), data)
        // Aufgefüllt: nicht die genaue Größe, höchstens 12 % mehr.
        XCTAssertGreaterThan(sealed.blob.count, data.count + 4)
        XCTAssertLessThan(Double(sealed.blob.count), Double(data.count) * 1.13 + 64)
        // Falscher Hash, falscher Schlüssel, verändertes Chiffrat.
        XCTAssertThrowsError(try AttachmentCrypto.open(sealed.blob, key: sealed.key, digest: Data(count: 32)))
        XCTAssertThrowsError(try AttachmentCrypto.open(sealed.blob, key: Data.random(count: 32), digest: sealed.digest))
        var bad = sealed.blob
        bad[bad.count - 1] ^= 1
        XCTAssertThrowsError(try AttachmentCrypto.open(bad, key: sealed.key, digest: Primitives.sha256(bad)))
        XCTAssertThrowsError(try AttachmentCrypto.seal(Data()))
        XCTAssertThrowsError(try AttachmentCrypto.seal(Data(count: AttachmentCrypto.maxSize + 1)))
    }

    func testPadmeLeavesFewBits() {
        XCTAssertEqual(AttachmentCrypto.padme(100), 104)
        for n in [1, 2, 7, 1000, 12_345, 1_000_000, AttachmentCrypto.maxSize] {
            let p = AttachmentCrypto.padme(n)
            XCTAssertGreaterThanOrEqual(p, n)
            XCTAssertLessThanOrEqual(Double(p), Double(n) * 1.12 + 1)
        }
        // Nah beieinander liegende Größen landen in derselben Stufe.
        XCTAssertEqual(AttachmentCrypto.padme(1_000_001), AttachmentCrypto.padme(1_000_100))
    }

    // MARK: - Senden und Empfangen

    func testPhotoRoundTrip() async throws {
        let (a, b) = try await connect()
        let out = photo()
        await alice.sendAttachment(chatId: a, out, caption: "Aussicht")
        await settle(self.received(b)?.attachment?.state == .ready)
        let m = try XCTUnwrap(received(b))
        XCTAssertEqual(m.text, "Aussicht")
        XCTAssertEqual(m.attachment?.kind, .image)
        XCTAssertEqual(m.attachment?.width, 800)
        XCTAssertEqual(m.attachment?.thumbnail, out.thumbnail)
        XCTAssertEqual(bob.attachmentData(m), out.data)
        // Der Absender behält seine Kopie im Tresor.
        let mine = try XCTUnwrap(alice.messages(in: a).last)
        XCTAssertEqual(alice.attachmentData(mine), out.data)
        XCTAssertEqual(mine.status, .delivered)

        // Abgeholt: der Blob verschwindet vom Server.
        await settle(self.blobs.storedIds.isEmpty)
        XCTAssertTrue(blobs.storedIds.isEmpty)
        XCTAssertNil(alice.meta.pendingBlobs)
    }

    func testServerNeverSeesThePlaintext() async throws {
        let (a, _) = try await connect()
        blobs.failDownloads = true
        let out = photo(5_000)
        await alice.sendAttachment(chatId: a, out)
        await settle()
        let id = try XCTUnwrap(blobs.storedIds.first)
        let blob = try XCTUnwrap(blobs.blob(id))
        XCTAssertNil(blob.range(of: out.data.prefix(64)))
        // In den Nachrichten auf dem Server steht weder Schlüssel noch Kennung.
        for (_, payload) in relay.sentPayloads {
            let text = (try? payload.jsonString()) ?? ""
            XCTAssertFalse(text.contains(id))
        }
    }

    func testFailedDownloadCanBeRetried() async throws {
        let (a, b) = try await connect()
        blobs.failDownloads = true
        await alice.sendAttachment(chatId: a, photo())
        await settle(self.received(b)?.attachment?.state == .failed, timeout: 15)
        XCTAssertEqual(received(b)?.attachment?.state, .failed)
        XCTAssertNil(bob.attachmentData(try XCTUnwrap(received(b))))

        blobs.failDownloads = false
        bob.retryAttachment(chatId: b, messageId: try XCTUnwrap(received(b)).id)
        await settle(self.received(b)?.attachment?.state == .ready)
        XCTAssertNotNil(bob.attachmentData(try XCTUnwrap(received(b))))
    }

    func testFailedUploadMarksTheMessage() async throws {
        let (a, b) = try await connect()
        blobs.failUploads = true
        await alice.sendAttachment(chatId: a, photo())
        let m = try XCTUnwrap(alice.messages(in: a).last)
        XCTAssertEqual(m.status, .failed)
        XCTAssertEqual(m.attachment?.state, .failed)

        // Erneut senden lädt die Datei neu hoch.
        blobs.failUploads = false
        await alice.resend(chatId: a, messageId: m.id)
        await settle(self.bob.messages(in: b).last?.attachment?.state == .ready)
        XCTAssertEqual(alice.messages(in: a).filter { $0.attachment != nil }.count, 1)
        XCTAssertNotNil(bob.attachmentData(try XCTUnwrap(bob.messages(in: b).last)))
    }

    func testDeletingTheMessageDeletesTheContent() async throws {
        let (a, b) = try await connect()
        await alice.sendAttachment(chatId: a, photo())
        await settle(self.received(b)?.attachment?.state == .ready)
        let m = try XCTUnwrap(received(b))
        XCTAssertTrue(bobVault.slotNames.contains("att.\(m.attachment!.id)"))
        bob.deleteForMe(chatId: b, messageId: m.id)
        await settle()
        XCTAssertFalse(bobVault.slotNames.contains("att.\(m.attachment!.id)"))
        XCTAssertNil(bob.meta.attachmentSlots)
    }

    func testViewOnceOpensExactlyOnce() async throws {
        let (a, b) = try await connect()
        let out = photo()
        await alice.sendAttachment(chatId: a, out, options: SendOptions(oneTime: true))
        // Der Absender behält nichts.
        XCTAssertNil(alice.messages(in: a).last?.attachment)
        XCTAssertTrue(alice.messages(in: a).last?.oneTime == true)
        await settle(self.received(b)?.attachment?.state == .ready)
        let m = try XCTUnwrap(received(b))
        XCTAssertTrue(m.oneTime)

        let opened = try XCTUnwrap(bob.openOneTimeAttachment(chatId: b, messageId: m.id))
        XCTAssertEqual(opened.0, out.data)
        XCTAssertNil(bob.openOneTimeAttachment(chatId: b, messageId: m.id))
        await settle()
        XCTAssertFalse(bobVault.slotNames.contains("att.\(m.attachment!.id)"))
        // Auch hier ist der Blob danach vom Server.
        await settle(self.blobs.storedIds.isEmpty)
        XCTAssertTrue(blobs.storedIds.isEmpty)
    }

    func testSelfDestructTakesTheContentAlong() async throws {
        let (a, b) = try await connect()
        await alice.sendAttachment(chatId: a, photo(), options: SendOptions(selfDestruct: 30))
        await settle(self.received(b)?.attachment?.state == .ready)
        let m = try XCTUnwrap(received(b))
        let id = try XCTUnwrap(m.attachment?.id)
        XCTAssertTrue(bobVault.slotNames.contains("att.\(id)"))
        // Die Frist ist um (Empfänger kappen Fristen auf mindestens 10 s).
        bob.updateMessage(b, m.id) { $0.deliveredAt = Date().addingTimeInterval(-60) }
        bob.cleanupExpired(includeBurned: false)
        await settle(self.bob.messages(in: b).isEmpty)
        XCTAssertTrue(bob.messages(in: b).isEmpty)
        XCTAssertFalse(bobVault.slotNames.contains("att.\(id)"))
    }

    func testMalformedAttachmentFieldIsIgnored() {
        let good = MessengerEngine.parseAttachment(.object([
            "id": .string(String(repeating: "a1", count: 16)), "k": .string(Data.random(count: 32).base64),
            "d": .string(Data.random(count: 32).base64), "s": 10, "c": "image", "m": "image/jpeg",
        ]))
        XCTAssertNotNil(good)
        for broken: JSONObject in [
            ["id": "../../etc", "k": .string(Data.random(count: 32).base64), "d": .string(Data.random(count: 32).base64), "s": 10, "c": "image", "m": "x"],
            ["id": .string(String(repeating: "a1", count: 16)), "k": "kurz", "d": .string(Data.random(count: 32).base64), "s": 10, "c": "image", "m": "x"],
            ["id": .string(String(repeating: "a1", count: 16)), "k": .string(Data.random(count: 32).base64), "d": .string(Data.random(count: 32).base64), "s": .int(AttachmentCrypto.maxSize + 1), "c": "image", "m": "x"],
            ["id": .string(String(repeating: "a1", count: 16)), "k": .string(Data.random(count: 32).base64), "d": .string(Data.random(count: 32).base64), "s": 10, "c": "exe", "m": "x"],
        ] {
            XCTAssertNil(MessengerEngine.parseAttachment(.object(broken)))
        }
    }
}
