import Foundation
import XCTest
@testable import KryptaCore

/// Swift liest, was Dart gebaut hat — und schreibt, was Dart lesen muss.
///
/// Gegenstück: test/interop/swift_interop_test.dart. Reihenfolge:
///   1. KRYPTA_GEN_VECTORS=1 flutter test test/interop  (schreibt dart_vectors.json)
///   2. swift test                                       (liest sie, schreibt swift_vectors.json)
///   3. flutter test test/interop                        (liest swift_vectors.json)
final class InteropTests: XCTestCase {
    private var vectors: JSONObject!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "dart_vectors", withExtension: "json", subdirectory: "Vectors"))
        vectors = try JSONObject.parse(String(contentsOf: url, encoding: .utf8))
    }

    private func pair(_ key: String) throws -> KeyPair {
        let o = try XCTUnwrap(vectors[key]?.objectValue)
        return KeyPair(
            privateKey: try XCTUnwrap(o["priv"]?.stringValue.flatMap(Data.init(base64:))),
            publicKey: try XCTUnwrap(o["pub"]?.stringValue.flatMap(Data.init(base64:)))
        )
    }

    /// Bobs Vorabschlüssel so ablegen, wie die App ihn hätte.
    private func bobPreKeys() throws -> PreKeyStore {
        let spk = try XCTUnwrap(vectors["bobSpk"]?.objectValue)
        var store = PreKeyStore()
        store.install(SignedPreKey(
            id: try XCTUnwrap(spk["id"]?.intValue),
            publicKey: try XCTUnwrap(spk["pub"]?.stringValue.flatMap(Data.init(base64:))),
            privateKey: try XCTUnwrap(spk["priv"]?.stringValue.flatMap(Data.init(base64:))),
            createdAt: Date()
        ))
        return store
    }

    private func receive(_ state: RatchetState, sender: String, payload: JSONObject) throws -> (RatchetState, JSONObject) {
        let (s, padded) = try DoubleRatchet.decrypt(
            state: state, message: RatchetMessage(payload: payload), associatedData: sender.utf8Data
        )
        return (s, try JSONObject.parse(String(decoding: try Envelope.unpad(padded), as: UTF8.self)))
    }

    private func send(_ state: RatchetState, sender: String, inner: JSONObject) throws -> (RatchetState, JSONObject) {
        let (s, msg) = try DoubleRatchet.encrypt(
            state: state, plaintext: Envelope.pad(try inner.jsonString().utf8Data), associatedData: sender.utf8Data
        )
        var map = msg.payloadMap
        map["v"] = 3
        return (s, map)
    }

    func testDartBundleSessionOutOfOrderAndReplyBack() throws {
        let aliceId = try XCTUnwrap(vectors["aliceId"]?.stringValue)
        let bobId = try XCTUnwrap(vectors["bobId"]?.stringValue)
        let alice = try pair("alice")
        let bob = try pair("bob")

        // Das Bündel, das Dart signiert hat, besteht die Swift-Prüfung.
        let bundle = try PreKeyBundle(json: try XCTUnwrap(vectors["bundle"]?.objectValue))
        XCTAssertTrue(bundle.hasValidSignature)

        let messages = try XCTUnwrap(vectors["bundleMessages"]?.arrayValue).map { try XCTUnwrap($0.objectValue) }
        let order = try XCTUnwrap(vectors["deliveryOrder"]?.arrayValue).compactMap(\.intValue)
        let first = try XCTUnwrap(messages[0]["payload"]?.objectValue)

        var state = try SessionHandshake.inbound(
            identity: bob, preKeys: try bobPreKeys(),
            senderIdentityPublicKey: alice.publicKey, header: first
        )
        for index in order {
            let payload = try XCTUnwrap(messages[index]["payload"]?.objectValue)
            let expected = try XCTUnwrap(messages[index]["inner"]?.objectValue)
            let (s, inner) = try receive(state, sender: aliceId, payload: payload)
            state = try ReplayGuard.validate(state: s, inner: inner, version: 3)
            XCTAssertEqual(inner["_t"], expected["_t"])
            XCTAssertEqual(inner["_sid"], .string(aliceId))
            XCTAssertEqual(inner["_sd"], expected["_sd"])
            XCTAssertEqual(inner["_bar"], expected["_bar"])
        }
        // Ein zweites Mal dieselbe Nachricht: der Replay-Schutz greift.
        XCTAssertThrowsError(try ReplayGuard.validate(state: state, inner: ["_seq": 1, "_t": "x"], version: 3))

        // Bob antwortet — Dart muss das mit Alices gespeichertem Zustand lesen.
        var replies: [JSONValue] = []
        for (i, text) in ["Antwort aus Swift", "Noch eine 🍏"].enumerated() {
            let (s, map) = try send(state, sender: bobId, inner: [
                "_t": .string(text), "_sid": .string(bobId), "_seq": .int(i),
            ])
            state = s
            replies.append(.object(["payload": .object(map), "text": .string(text)]))
        }

        // Swift eröffnet selbst eine Sitzung gegen Bob2 (Dart prüft die Gegenseite).
        let bob2 = try XCTUnwrap(vectors["bob2"]?.objectValue)
        let bob2Bundle = try PreKeyBundle(json: try XCTUnwrap(bob2["bundle"]?.objectValue))
        let outbound = try SessionHandshake.outbound(identity: alice, bundle: bob2Bundle, pinnedIdentityPublicKey: bob.publicKey)
        var (_, firstOut) = try send(outbound.state, sender: aliceId, inner: [
            "_t": "Sitzung aus Swift", "_sid": .string(aliceId), "_seq": 0,
        ])
        firstOut.merge(outbound.header) { _, new in new }

        // Ein fremdes Bündel mit richtiger Signatur, aber falscher Identität,
        // wird abgewiesen (KRY-01).
        XCTAssertThrowsError(try SessionHandshake.outbound(identity: alice, bundle: bob2Bundle, pinnedIdentityPublicKey: alice.publicKey)) {
            XCTAssertEqual($0 as? HandshakeError, .identityMismatch)
        }

        // Passwort-Blob, Steuernachricht, signiertes Bündel, Sicherheitsnummer.
        let aad = "pwd-v1|\(bobId)|\(aliceId)|msg-9"
        let blob = try Envelope.encryptWithPassword("Passwort aus Swift", password: "zweites pferd", aad: aad)
        let pairKey = try ControlMessage.pairKey(identity: alice, peerIdentityPublicKey: bob.publicKey, ownId: aliceId, peerId: bobId)
        let ctrl = ControlMessage.create(type: "read", chatId: "swift-chat", messageId: "msg-9", senderId: aliceId, counter: 3, key: pairKey)
        var store = PreKeyStore()
        _ = store.rotate()
        let swiftBundle = try store.bundle(identity: bob)
        let safety = SafetyNumber.generate(localUserId: bobId, localIdentity: bob.publicKey, remoteUserId: aliceId, remoteIdentity: alice.publicKey)

        // Schlüsselprotokoll: Dart-Kette prüfen, eigene für Dart schreiben.
        let dartKt = try XCTUnwrap(vectors["kt"]?.objectValue)
        var dartChain = TransparencyChain()
        for (i, value) in try XCTUnwrap(dartKt["log"]?.arrayValue).enumerated() {
            let c = try KeyCommitment(json: try XCTUnwrap(value.objectValue))
            XCTAssertEqual(c.commitHash.base64, dartKt["hashes"]?.arrayValue?[i].stringValue)
            XCTAssertEqual(dartChain.verifyAndAppend(c, expectedPublicKey: alice.publicKey), .valid)
        }
        XCTAssertNil(dartChain.audit())
        var ktChain = TransparencyChain()
        let kt0 = try KeyCommitment.create(epoch: 0, identity: bob, previousHash: KeyCommitment.genesisHash)
        let kt1 = try KeyCommitment.create(epoch: 1, identity: bob, previousHash: kt0.commitHash)
        XCTAssertEqual(ktChain.verifyAndAppend(kt0, expectedPublicKey: bob.publicKey), .valid)
        XCTAssertEqual(ktChain.verifyAndAppend(kt1, expectedPublicKey: bob.publicKey), .valid)

        let out: JSONObject = [
            "replies": .array(replies),
            "outbound": .object(["payload": .object(firstOut), "text": "Sitzung aus Swift"]),
            "password": .object(["blob": .string(blob), "password": "zweites pferd", "aad": .string(aad), "plaintext": "Passwort aus Swift"]),
            "control": .object(ctrl.json),
            "bundle": .object(swiftBundle.json),
            "safetyNumber": .string(safety),
            "kt": .object([
                "log": .array([.object(kt0.json), .object(kt1.json)]),
                "hashes": .array([.string(kt0.commitHash.base64), .string(kt1.commitHash.base64)]),
            ]),
        ]
        let data = try JSONSerialization.data(withJSONObject: out.anyDictionary, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let target = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vectors/swift_vectors.json")
        try data.write(to: target)
    }

    func testDartFallbackSession() throws {
        let fb = try XCTUnwrap(vectors["fallback"]?.objectValue)
        let payload = try XCTUnwrap(fb["payload"]?.objectValue)
        let carolPub = try XCTUnwrap(fb["carolPub"]?.stringValue.flatMap(Data.init(base64:)))
        // Rückfallweg: gespiegelt wird die Identität, auch wenn Vorabschlüssel existieren.
        let state = try SessionHandshake.inbound(
            identity: try pair("bob"), preKeys: try bobPreKeys(),
            senderIdentityPublicKey: carolPub, header: payload
        )
        let (_, inner) = try receive(state, sender: try XCTUnwrap(fb["senderId"]?.stringValue), payload: payload)
        XCTAssertEqual(inner["_t"], fb["text"])
    }

    func testDartPasswordBlob() throws {
        let pw = try XCTUnwrap(vectors["password"]?.objectValue)
        let blob = try XCTUnwrap(pw["blob"]?.stringValue)
        let aad = pw["aad"]?.stringValue
        XCTAssertEqual(Envelope.decryptWithPassword(blob, password: try XCTUnwrap(pw["password"]?.stringValue), aad: aad), pw["plaintext"]?.stringValue)
        XCTAssertNil(Envelope.decryptWithPassword(blob, password: "falsch", aad: aad))
        XCTAssertNil(Envelope.decryptWithPassword(blob, password: try XCTUnwrap(pw["password"]?.stringValue), aad: nil))
    }

    func testDartSafetyNumberAndControlMessage() throws {
        let aliceId = try XCTUnwrap(vectors["aliceId"]?.stringValue)
        let bobId = try XCTUnwrap(vectors["bobId"]?.stringValue)
        let alice = try pair("alice"), bob = try pair("bob")
        XCTAssertEqual(
            SafetyNumber.generate(localUserId: aliceId, localIdentity: alice.publicKey, remoteUserId: bobId, remoteIdentity: bob.publicKey),
            vectors["safetyNumber"]?.stringValue
        )

        let control = try XCTUnwrap(vectors["control"]?.objectValue)
        let key = try XCTUnwrap(control["key"]?.stringValue.flatMap(Data.init(base64:)))
        let msg = try ControlMessage(json: try XCTUnwrap(control["message"]?.objectValue))
        XCTAssertTrue(msg.verify(key: key))
        XCTAssertFalse(msg.verify(key: Data(count: 32)))

        // Beide Seiten leiten denselben Paarschlüssel ab wie Dart.
        let expected = try XCTUnwrap(control["pairHmacKey"]?.stringValue.flatMap(Data.init(base64:)))
        XCTAssertEqual(try ControlMessage.pairKey(identity: alice, peerIdentityPublicKey: bob.publicKey, ownId: aliceId, peerId: bobId), expected)
        XCTAssertEqual(try ControlMessage.pairKey(identity: bob, peerIdentityPublicKey: alice.publicKey, ownId: bobId, peerId: aliceId), expected)
    }
}
