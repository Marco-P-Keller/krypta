import Foundation
import XCTest
import KryptaCore
@testable import KryptaMessenger

/// Übernahme eines Speichers, den der Dart-Code der Flutter-App geschrieben
/// hat (test/interop/flutter_store_fixture_test.dart).
@MainActor
final class FlutterImportTests: XCTestCase {
    private var fixture: JSONObject!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "flutter_store", withExtension: "json", subdirectory: "Vectors"))
        fixture = try JSONObject.parse(String(contentsOf: url, encoding: .utf8))
    }

    private func decryptedStore() throws -> (FlutterImport.Secrets, FlutterImport.Store) {
        let secrets = try XCTUnwrap(fixture["secrets"]?.objectValue).compactMapValues(\.stringValue)
        let key = try XCTUnwrap(secrets["krypta_db_key"].flatMap(Data.init(base64:)))
        var store: FlutterImport.Store = [:]
        for (file, value) in try XCTUnwrap(fixture["files"]?.objectValue) {
            let slot = String(file.dropLast(".enc".count))
            let blob = try XCTUnwrap(value.stringValue.flatMap(Data.init(base64:)))
            let plain = try XCTUnwrap(FlutterImport.openStoreBlob(blob, key: key, slot: slot), "\(slot) nicht lesbar")
            store[slot] = String(decoding: plain, as: UTF8.self)
        }
        return (secrets, store)
    }

    func testConvertsEverything() throws {
        let (secrets, store) = try decryptedStore()
        let r = try FlutterImport.convert(secrets: secrets, store: store)
        let chatId = try XCTUnwrap(fixture["chatId"]?.stringValue)
        let bobId = try XCTUnwrap(fixture["bobId"]?.stringValue)

        XCTAssertEqual(r.userId, fixture["aliceId"]?.stringValue)
        XCTAssertEqual(r.contacts.map(\.displayName), ["Mami"])
        XCTAssertEqual(r.contacts.first?.trustState, .verified)
        XCTAssertEqual(r.contacts.first?.verificationMethod, .qrCode)
        XCTAssertEqual(r.chats.first?.timer, 3600)
        XCTAssertEqual(r.chats.first?.ruleVersion, 2)
        let msgs = try XCTUnwrap(r.messages[chatId])
        XCTAssertEqual(msgs.map(\.id), ["m-1", "m-2", "m-3"])
        XCTAssertEqual(msgs[0].text, "Hallo Bob")
        XCTAssertEqual(msgs[1].isPasswordProtected, true)
        XCTAssertEqual(msgs[1].passwordUnlocked, false)
        XCTAssertEqual(msgs[1].text, "blob-mit-passwort")
        XCTAssertEqual(msgs[1].selfDestruct, 300)
        XCTAssertEqual(msgs[2].systemEvent, .screenshot)
        XCTAssertNotNil(r.ratchets[chatId])
        XCTAssertEqual(r.preKeys?.current?.id, 4)
        XCTAssertEqual(r.preKeys?.nextId, 5)
        XCTAssertEqual(r.counters?.lastSeen(for: chatId), 9)
        XCTAssertEqual(r.meta.processedIds, ["alt-1", "alt-2"])
        XCTAssertEqual(r.meta.psidLineage[bobId], ["psid-a"])
        XCTAssertTrue(r.meta.readReceipts)
        XCTAssertFalse(r.meta.chatPreview)
        XCTAssertEqual(r.transparency[r.userId]?.latestEpoch, 0)
        XCTAssertNotNil(r.transparency[r.userId]?.signingPin)

        XCTAssertEqual(r.settings.secretCodeHash, "c2FsdA==:aGFzaA==")
        XCTAssertTrue(r.settings.calculatorLock)
        XCTAssertTrue(r.settings.biometricLock)
        XCTAssertEqual(r.settings.vaultPasswordHash, "dmF1bHQ=:aGFzaA==")
        XCTAssertEqual(r.settings.vaultFailures, 2)
        XCTAssertFalse(r.settings.pushEnabled)
        XCTAssertEqual(r.settings.languageCode, "it")
    }

    /// Der eigentliche Beweis: nach der Übernahme liest Alice mit ihrer
    /// alten Flutter-Sitzung, was Bob danach schickt.
    func testImportedSessionKeepsWorking() async throws {
        let (secrets, store) = try decryptedStore()
        let r = try FlutterImport.convert(secrets: secrets, store: store)
        let vault = MemoryVault()
        FlutterImport.write(r, to: vault)

        let relay = MemoryRelay()
        let alice = MessengerEngine(userId: r.userId, identity: r.identity, relay: relay, vault: vault, config: .immediate)
        await alice.start()
        defer { alice.stop() }
        let chatId = try XCTUnwrap(fixture["chatId"]?.stringValue)
        let bobId = try XCTUnwrap(fixture["bobId"]?.stringValue)
        // m-1 folgt der Chat-Regel (1 h) und kann je nach Alter der
        // Testdaten schon abgelaufen sein; die anderen beiden haben keine Frist.
        XCTAssertTrue(Set(alice.messages(in: chatId).map(\.id)).isSuperset(of: ["m-2", "m-3"]))
        XCTAssertEqual(alice.chat(chatId)?.name, "Mami")
        // Die eigene Schlüsselkette wird übernommen, nicht neu begonnen.
        XCTAssertEqual(alice.transparencyChain(r.userId)?.latestEpoch, 0)

        try await relay.send(from: bobId, to: r.userId, messageId: "m-4", payload: try XCTUnwrap(fixture["reply"]?.objectValue))
        for _ in 0..<100 where !alice.messages(in: chatId).contains(where: { $0.id == "m-4" }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(alice.messages(in: chatId).first { $0.id == "m-4" }?.text, fixture["replyText"]?.stringValue)
    }

    func testRejectsIncompleteStore() {
        XCTAssertThrowsError(try FlutterImport.convert(secrets: [:], store: [:])) {
            XCTAssertEqual($0 as? FlutterImport.Failure, .noIdentity)
        }
    }
}
