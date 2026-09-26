import Foundation
import XCTest
@testable import KryptaCore

/// Versiegelter Absender und der hybride Handschlag mit ML-KEM-768.
///
/// Die ML-KEM-Tests brauchen iOS 26 / macOS 26 und laufen sonst nicht
/// (übersprungen); ausführen im Simulator, siehe README.
final class SealedAndPostQuantumTests: XCTestCase {
    private let contents = SealedSender.Contents(
        senderId: "aliceUid00000000000001", messageId: "1b0c1c7e-0000-4000-8000-000000000001",
        payload: ["v": 3, "c": "Y2lwaGVy", "n": 0]
    )

    // MARK: - Sealed Sender

    func testSealedRoundTrip() throws {
        let bob = KeyPair.generate()
        let blob = try SealedSender.seal(contents, recipientId: "bobUid0000000000000002", recipientIdentity: bob.publicKey)
        XCTAssertEqual(try SealedSender.open(blob, recipientId: "bobUid0000000000000002", identity: bob), contents)
    }

    func testSealedHidesSenderAndMessageId() throws {
        let bob = KeyPair.generate()
        let blob = try SealedSender.seal(contents, recipientId: "bobUid0000000000000002", recipientIdentity: bob.publicKey)
        let visible = String(decoding: blob, as: UTF8.self) + blob.base64
        XCTAssertFalse(visible.contains(contents.senderId))
        XCTAssertFalse(visible.contains(contents.messageId))
    }

    func testSealedOnlyOpensForTheRecipient() throws {
        let bob = KeyPair.generate(), eve = KeyPair.generate()
        let blob = try SealedSender.seal(contents, recipientId: "bobUid0000000000000002", recipientIdentity: bob.publicKey)
        XCTAssertThrowsError(try SealedSender.open(blob, recipientId: "bobUid0000000000000002", identity: eve))
        // Umgeleitet an eine andere Kennung: die AAD passt nicht mehr.
        XCTAssertThrowsError(try SealedSender.open(blob, recipientId: "eveUid0000000000000003", identity: bob))
    }

    func testTamperedSealedEnvelopeIsRejected() throws {
        let bob = KeyPair.generate()
        let blob = try SealedSender.seal(contents, recipientId: "bobUid0000000000000002", recipientIdentity: bob.publicKey)
        for index in [0, 5, 40, 60, blob.count - 1] {
            var bytes = [UInt8](blob)
            bytes[index] ^= 0x01
            XCTAssertThrowsError(try SealedSender.open(Data(bytes), recipientId: "bobUid0000000000000002", identity: bob), "Byte \(index)")
        }
        XCTAssertThrowsError(try SealedSender.open(blob.prefix(40).detached, recipientId: "bobUid0000000000000002", identity: bob))
    }

    // MARK: - Herabstufung (läuft überall)

    func testClassicalBundleIsRefusedWhenPostQuantumIsRequired() throws {
        let alice = KeyPair.generate(), bob = KeyPair.generate()
        var store = PreKeyStore()
        _ = store.rotate()
        let classical = try PreKeyBundle(json: store.bundle(identity: bob).strippedOfPostQuantum)
        XCTAssertThrowsError(
            try SessionHandshake.outbound(identity: alice, bundle: classical, pinnedIdentityPublicKey: bob.publicKey, requirePostQuantum: true)
        ) { XCTAssertEqual($0 as? HandshakeError, .postQuantumMissing) }
    }

    func testClassicalHandshakeIsRefusedWhenPostQuantumIsRequired() throws {
        let alice = KeyPair.generate(), bob = KeyPair.generate()
        var store = PreKeyStore()
        _ = store.rotate()
        let bundle = try PreKeyBundle(json: store.bundle(identity: bob).strippedOfPostQuantum)
        let out = try SessionHandshake.outbound(identity: alice, bundle: bundle, pinnedIdentityPublicKey: bob.publicKey)
        XCTAssertFalse(out.isPostQuantum)
        XCTAssertThrowsError(try SessionHandshake.inbound(
            identity: bob, preKeys: store, senderIdentityPublicKey: alice.publicKey, header: out.header, requirePostQuantum: true
        ))
        // Ohne die Pflicht geht es wie bisher.
        XCTAssertNoThrow(try SessionHandshake.inbound(identity: bob, preKeys: store, senderIdentityPublicKey: alice.publicKey, header: out.header))
    }

    func testOldStoreWithoutPostQuantumKeysStillDecodes() throws {
        var store = PreKeyStore()
        _ = store.rotate()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(store)) as? [String: Any])
        json.removeValue(forKey: "postQuantumKeys")
        let decoded = try JSONDecoder().decode(PreKeyStore.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.current, store.current)
    }

    // MARK: - ML-KEM (iOS 26 / macOS 26)

    private func requirePostQuantum() throws {
        try XCTSkipUnless(PostQuantum.isAvailable, "ML-KEM braucht iOS 26 / macOS 26")
    }

    private func postQuantumStore() throws -> PreKeyStore {
        var store = PreKeyStore()
        _ = store.rotate()
        XCTAssertTrue(store.ensurePostQuantum())
        XCTAssertFalse(store.ensurePostQuantum(), "nur einmal je Vorabschlüssel")
        return store
    }

    func testPostQuantumHandshake() throws {
        try requirePostQuantum()
        let alice = KeyPair.generate(), bob = KeyPair.generate()
        let store = try postQuantumStore()
        let bundle = try PreKeyBundle(json: store.bundle(identity: bob).json)
        XCTAssertTrue(bundle.hasValidPostQuantumKey)

        let out = try SessionHandshake.outbound(identity: alice, bundle: bundle, pinnedIdentityPublicKey: bob.publicKey, requirePostQuantum: true)
        XCTAssertTrue(out.isPostQuantum)
        XCTAssertTrue(SessionHandshake.isPostQuantum(out.header))
        XCTAssertEqual(SessionHandshake.handshakeId(out.header)?.count, 44, "Kennung ohne Chiffrat")

        let bobState = try SessionHandshake.inbound(identity: bob, preKeys: store, senderIdentityPublicKey: alice.publicKey, header: out.header, requirePostQuantum: true)
        let (_, message) = try DoubleRatchet.encrypt(state: out.state, plaintext: "quantensicher".utf8Data, associatedData: "A".utf8Data)
        let (_, plain) = try DoubleRatchet.decrypt(state: bobState, message: message, associatedData: "A".utf8Data)
        XCTAssertEqual(plain, "quantensicher".utf8Data)
    }

    func testTamperedKemCiphertextBreaksTheSession() throws {
        try requirePostQuantum()
        let alice = KeyPair.generate(), bob = KeyPair.generate()
        let store = try postQuantumStore()
        let out = try SessionHandshake.outbound(identity: alice, bundle: store.bundle(identity: bob), pinnedIdentityPublicKey: bob.publicKey)
        var raw = [UInt8](try XCTUnwrap(out.header["ek"]?.stringValue.flatMap(Data.init(base64:))))
        raw[100] ^= 0x01
        var header = out.header
        header["ek"] = .string(Data(raw).base64)
        let bobState = try SessionHandshake.inbound(identity: bob, preKeys: store, senderIdentityPublicKey: alice.publicKey, header: header)
        let (_, message) = try DoubleRatchet.encrypt(state: out.state, plaintext: "x".utf8Data, associatedData: "A".utf8Data)
        XCTAssertThrowsError(try DoubleRatchet.decrypt(state: bobState, message: message, associatedData: "A".utf8Data))
    }

    func testForgedPostQuantumKeyIsIgnored() throws {
        try requirePostQuantum()
        let bob = KeyPair.generate()
        let store = try postQuantumStore()
        let real = try store.bundle(identity: bob)
        // Der Server tauscht den ML-KEM-Schlüssel gegen seinen eigenen.
        let forged = PreKeyBundle(
            identityPublicKey: real.identityPublicKey, signedPreKeyPublic: real.signedPreKeyPublic,
            signedPreKeySignature: real.signedPreKeySignature, signedPreKeyId: real.signedPreKeyId,
            signingPublicKey: real.signingPublicKey,
            postQuantumPreKey: try PostQuantum.generate().publicKey, postQuantumSignature: real.postQuantumSignature
        )
        XCTAssertFalse(forged.hasValidPostQuantumKey)
        let out = try SessionHandshake.outbound(identity: .generate(), bundle: forged, pinnedIdentityPublicKey: bob.publicKey)
        XCTAssertFalse(out.isPostQuantum, "ein gefälschter Schlüssel wird nicht verwendet")
    }

    func testPostQuantumKeysFollowRotation() throws {
        try requirePostQuantum()
        var store = try postQuantumStore()
        let first = try XCTUnwrap(store.current?.id)
        // Das Überlappungsfenster zählt ab der Erstellung des alten Schlüssels.
        let later = Date().addingTimeInterval(3600)
        _ = store.rotate(now: later)
        XCTAssertTrue(store.ensurePostQuantum(now: later))
        XCTAssertNotNil(store.findPostQuantum(id: first, now: later), "im Überlappungsfenster noch da")
        let muchLater = later.addingTimeInterval(PreKeyStore.overlap + 60)
        store.prune(now: muchLater)
        XCTAssertNil(store.findPostQuantum(id: first, now: muchLater))
        XCTAssertEqual(store.postQuantumKeys?.count, 1)
    }
}

private extension PreKeyBundle {
    /// Das Bündel, wie es der Server ohne ML-KEM ausliefern könnte.
    var strippedOfPostQuantum: JSONObject {
        var map = json
        map.removeValue(forKey: "pqpk")
        map.removeValue(forKey: "pqs")
        return map
    }
}
