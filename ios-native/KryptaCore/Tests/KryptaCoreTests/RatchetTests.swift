import Foundation
import XCTest
@testable import KryptaCore

/// Verhalten des Ratchets ohne Dart: Hin und Her, Manipulation, Grenzen.
final class RatchetTests: XCTestCase {
    private func session() throws -> (alice: RatchetState, bob: RatchetState) {
        let alice = KeyPair.generate(), bob = KeyPair.generate()
        var store = PreKeyStore()
        _ = store.rotate()
        let bundle = try store.bundle(identity: bob)
        let out = try SessionHandshake.outbound(identity: alice, bundle: bundle, pinnedIdentityPublicKey: bob.publicKey)
        let bobState = try SessionHandshake.inbound(identity: bob, preKeys: store, senderIdentityPublicKey: alice.publicKey, header: out.header)
        return (out.state, bobState)
    }

    func testPingPongWithDhSteps() throws {
        var (a, b) = try session()
        for round in 0..<5 {
            let (a2, m1) = try DoubleRatchet.encrypt(state: a, plaintext: "a\(round)".utf8Data, associatedData: "A".utf8Data)
            a = a2
            let (b2, p1) = try DoubleRatchet.decrypt(state: b, message: m1, associatedData: "A".utf8Data)
            b = b2
            XCTAssertEqual(String(decoding: p1, as: UTF8.self), "a\(round)")

            let (b3, m2) = try DoubleRatchet.encrypt(state: b, plaintext: "b\(round)".utf8Data, associatedData: "B".utf8Data)
            b = b3
            let (a3, p2) = try DoubleRatchet.decrypt(state: a, message: m2, associatedData: "B".utf8Data)
            a = a3
            XCTAssertEqual(String(decoding: p2, as: UTF8.self), "b\(round)")
        }
    }

    func testTamperedMessageLeavesStateUsable() throws {
        var (a, b) = try session()
        let (a2, good) = try DoubleRatchet.encrypt(state: a, plaintext: "echt".utf8Data, associatedData: "A".utf8Data)
        a = a2
        var bad = good.ciphertext.ciphertext
        bad[bad.startIndex] ^= 0xFF
        let forged = RatchetMessage(header: good.header, ciphertext: .init(ciphertext: bad, nonce: good.ciphertext.nonce, mac: good.ciphertext.mac))
        XCTAssertThrowsError(try DoubleRatchet.decrypt(state: b, message: forged, associatedData: "A".utf8Data))
        // Falsche AAD (anderer Absender) scheitert ebenfalls.
        XCTAssertThrowsError(try DoubleRatchet.decrypt(state: b, message: good, associatedData: "X".utf8Data))
        // Der unveränderte Zustand entschlüsselt die echte Nachricht weiterhin.
        let (b2, plain) = try DoubleRatchet.decrypt(state: b, message: good, associatedData: "A".utf8Data)
        b = b2
        XCTAssertEqual(plain, "echt".utf8Data)
        _ = (a, b)
    }

    func testTooManySkippedIsRejected() throws {
        var (a, b) = try session()
        var last: RatchetMessage?
        for _ in 0...(DoubleRatchet.maxSkip + 1) {
            let (a2, m) = try DoubleRatchet.encrypt(state: a, plaintext: Data([1]), associatedData: Data())
            a = a2
            last = m
        }
        XCTAssertThrowsError(try DoubleRatchet.decrypt(state: b, message: last!, associatedData: Data()))
        _ = b
    }

    func testStateSurvivesJSONRoundTrip() throws {
        var (a, b) = try session()
        let (a2, m) = try DoubleRatchet.encrypt(state: a, plaintext: "x".utf8Data, associatedData: Data())
        a = a2
        let restored = try RatchetState(json: try JSONObject.parse(try b.json.jsonString()))
        XCTAssertEqual(restored.rootKey, b.rootKey)
        let (_, plain) = try DoubleRatchet.decrypt(state: restored, message: m, associatedData: Data())
        XCTAssertEqual(plain, "x".utf8Data)
    }

    func testPaddingHidesLength() throws {
        XCTAssertEqual(Envelope.pad(Data(count: 1)).count, 256)
        XCTAssertEqual(Envelope.pad(Data(count: 252)).count, 256)
        XCTAssertEqual(Envelope.pad(Data(count: 253)).count, 512)
        let text = "Grüße".utf8Data
        XCTAssertEqual(try Envelope.unpad(Envelope.pad(text)), text)
    }

    func testLocalBlobIsBoundToSlot() throws {
        let key = Data.random(count: 32)
        let blob = try Envelope.sealLocal("kontakte".utf8Data, key: key, slot: "contacts")
        XCTAssertEqual(try Envelope.openLocal(blob, key: key, slot: "contacts"), "kontakte".utf8Data)
        XCTAssertThrowsError(try Envelope.openLocal(blob, key: key, slot: "chats"))
    }

    func testRollbackPsidRejected() throws {
        var state = try session().bob
        state = try ReplayGuard.validate(state: state, inner: ["_seq": 0, "_psid": "alt"], version: 3)
        state.recentRecvSeqs = []
        XCTAssertThrowsError(try ReplayGuard.validate(state: state, inner: ["_seq": 0, "_psid": "alt"], version: 3)) {
            XCTAssertEqual($0 as? ReplayGuard.Rejection, .rollbackPsid)
        }
    }
}
