import Foundation

public enum HandshakeError: Error, Equatable {
    /// Das Bündel nennt eine andere Identität als die hinterlegte (KRY-01).
    case identityMismatch
    case invalidSignature
    /// Die Gegenseite hatte schon ML-KEM, jetzt fehlt es — Herabstufung.
    case postQuantumMissing
}

/// Ergebnis einer ausgehenden Sitzung. `header` gehört in die erste
/// Nachricht (`ek` + `spkId`, im Rückfallweg `ek` + `ek2`).
public struct OutboundSession: Sendable {
    public let state: RatchetState
    public let header: JSONObject
    public let isPostQuantum: Bool
}

/// X3DH wie security/session/session_handshake_service.dart.
///
/// Immer 3-DH; Einmal-Vorabschlüssel fließen bewusst nicht ein, solange
/// die Gegenseite sie nicht nachbilden kann.
///
/// Post-Quanten (hybrid, wie Signals PQXDH): Hat das Bündel einen signierten
/// ML-KEM-768-Schlüssel und kann dieses Gerät ML-KEM, fließt das
/// gekapselte Geheimnis in die Ableitung ein —
/// HKDF(DH1 ‖ DH2 ‖ DH3 ‖ SS, info: "KryptaPQXDH-v1"). Das Chiffrat reist
/// hinter dem Ephemeral im selben Feld `ek` (32 + 1088 Bytes): ein eigenes
/// Feld ginge nicht, weil `p` laut firestore.rules höchstens zehn Felder
/// haben darf und die mit `ek`, `spkId` und `nt` belegt sind.
public enum SessionHandshake {
    static let info = "KryptaX3DH-v1".utf8Data
    static let postQuantumInfo = "KryptaPQXDH-v1".utf8Data

    /// Absenderseite über das veröffentlichte Bündel.
    ///
    /// `pinnedIdentityPublicKey` ist der Schlüssel, den *dieses* Gerät für
    /// den Kontakt kennt. Er ist der Anker; das Bündel kommt vom Server und
    /// darf nicht bestimmen, wer der Kontakt ist.
    ///
    /// `requirePostQuantum`: die Gegenseite hat schon einmal ML-KEM gezeigt.
    /// Fehlt es jetzt im Bündel, hat es jemand entfernt — dann lieber gar
    /// keine Sitzung als eine schwächere.
    public static func outbound(identity: KeyPair, bundle: PreKeyBundle, pinnedIdentityPublicKey: Data, requirePostQuantum: Bool = false) throws -> OutboundSession {
        guard bundle.identityPublicKey.constantTimeEquals(pinnedIdentityPublicKey) else {
            throw HandshakeError.identityMismatch
        }
        guard bundle.hasValidSignature else { throw HandshakeError.invalidSignature }

        var kem: (sharedSecret: Data, ciphertext: Data)?
        if PostQuantum.isAvailable, bundle.hasValidPostQuantumKey, let pqKey = bundle.postQuantumPreKey {
            kem = try PostQuantum.encapsulate(to: pqKey)
        } else if requirePostQuantum {
            throw HandshakeError.postQuantumMissing
        }

        var eph = KeyPair.generate()
        defer { eph.privateKey.zero() }
        var dh1 = try Primitives.dh(privateKey: identity.privateKey, publicKey: bundle.signedPreKeyPublic)
        var dh2 = try Primitives.dh(privateKey: eph.privateKey, publicKey: bundle.identityPublicKey)
        var dh3 = try Primitives.dh(privateKey: eph.privateKey, publicKey: bundle.signedPreKeyPublic)
        var ss = kem?.sharedSecret ?? Data()
        var secret = kem == nil ? derive(dh1 + dh2 + dh3) : derivePostQuantum(dh1 + dh2 + dh3 + ss)
        defer { dh1.zero(); dh2.zero(); dh3.zero(); ss.zero(); secret.zero() }

        let state = try DoubleRatchet.initAsSender(sharedSecret: secret, recipientRatchetPublicKey: bundle.signedPreKeyPublic)
        return OutboundSession(state: state, header: [
            "ek": .string((eph.publicKey + (kem?.ciphertext ?? Data())).base64),
            "spkId": .int(bundle.signedPreKeyId),
        ], isPostQuantum: kem != nil)
    }

    /// Absenderseite ohne Bündel: drei unabhängige DH-Werte gegen die
    /// Identität der Gegenseite, markiert durch `ek2`.
    public static func outboundFallback(identity: KeyPair, recipientIdentityPublicKey: Data) throws -> OutboundSession {
        var eph = KeyPair.generate()
        var eph2 = KeyPair.generate()
        defer { eph.privateKey.zero(); eph2.privateKey.zero() }
        var dh1 = try Primitives.dh(privateKey: identity.privateKey, publicKey: recipientIdentityPublicKey)
        var dh2 = try Primitives.dh(privateKey: eph.privateKey, publicKey: recipientIdentityPublicKey)
        var dh3 = try Primitives.dh(privateKey: eph2.privateKey, publicKey: recipientIdentityPublicKey)
        var secret = derive(dh1 + dh2 + dh3)
        defer { dh1.zero(); dh2.zero(); dh3.zero(); secret.zero() }

        let state = try DoubleRatchet.initAsSender(sharedSecret: secret, recipientRatchetPublicKey: recipientIdentityPublicKey)
        return OutboundSession(state: state, header: [
            "ek": .string(eph.publicKey.base64),
            "ek2": .string(eph2.publicKey.base64),
        ], isPostQuantum: false)
    }

    /// Empfängerseite für die erste Nachricht einer Sitzung.
    ///
    /// Welches eigene Paar gespiegelt wird, bestimmt der Absender: mit `ek2`
    /// die Identität, sonst der signierte Vorabschlüssel mit `spkId` (auch
    /// ein rotierter aus dem 48-Stunden-Fenster).
    public static func inbound(
        identity: KeyPair,
        preKeys: PreKeyStore,
        senderIdentityPublicKey: Data,
        header payload: JSONObject,
        requirePostQuantum: Bool = false,
        now: Date = Date()
    ) throws -> RatchetState {
        let rawEk = payload["ek"]?.stringValue.flatMap(Data.init(base64:))
        let ek2 = payload["ek2"]?.stringValue.flatMap(Data.init(base64:))
        // Mit ML-KEM hängt das Chiffrat hinter dem Ephemeral.
        let kemCiphertext = rawEk.flatMap { $0.count == 32 + PostQuantum.ciphertextLength ? $0.suffix(PostQuantum.ciphertextLength).detached : nil }
        let ek = kemCiphertext == nil ? rawEk : rawEk?.prefix(32).detached
        if requirePostQuantum && (kemCiphertext == nil || ek2 != nil) { throw HandshakeError.postQuantumMissing }
        // Ohne `ek` (sehr alte Absender) wird die Identität des Kontakts als
        // Ephemeral eingesetzt, wie in Dart.
        let senderEphemeral = ek ?? senderIdentityPublicKey

        let spkId: Int? = payload["spkId"]?.intValue ?? payload["spkId"]?.stringValue.flatMap(Int.init)
        let ratchetPair: KeyPair
        if ek2 != nil {
            ratchetPair = identity
        } else if let spkId, let match = preKeys.find(id: spkId, now: now) {
            ratchetPair = KeyPair(privateKey: match.privateKey, publicKey: match.publicKey)
        } else if let current = preKeys.current {
            ratchetPair = KeyPair(privateKey: current.privateKey, publicKey: current.publicKey)
        } else {
            ratchetPair = identity
        }

        var dh1 = try Primitives.dh(privateKey: ratchetPair.privateKey, publicKey: senderIdentityPublicKey)
        var dh2 = try Primitives.dh(privateKey: identity.privateKey, publicKey: senderEphemeral)
        var dh3: Data
        if let ek2 {
            dh3 = try Primitives.dh(privateKey: identity.privateKey, publicKey: ek2)
        } else {
            dh3 = try Primitives.dh(privateKey: ratchetPair.privateKey, publicKey: senderEphemeral)
        }
        var ss = Data()
        if let kemCiphertext {
            // Nur gegen den signierten Vorabschlüssel; ohne passenden
            // ML-KEM-Schlüssel ist die Nachricht nicht zu öffnen.
            guard ek2 == nil, let spkId, let pq = preKeys.findPostQuantum(id: spkId, now: now) else {
                throw CryptoError.malformed("post-quantum prekey")
            }
            ss = try PostQuantum.decapsulate(kemCiphertext, seed: pq.seed, publicKey: pq.publicKey)
        }
        var secret = kemCiphertext == nil ? derive(dh1 + dh2 + dh3) : derivePostQuantum(dh1 + dh2 + dh3 + ss)
        defer { dh1.zero(); dh2.zero(); dh3.zero(); ss.zero(); secret.zero() }

        return DoubleRatchet.initAsReceiver(
            sharedSecret: secret,
            ratchetPublicKey: ratchetPair.publicKey,
            ratchetPrivateKey: ratchetPair.privateKey
        )
    }

    static func derive(_ ikm: Data) -> Data {
        Primitives.hkdfSHA256(ikm: ikm, salt: Data(count: 32), info: info, length: 32)
    }

    static func derivePostQuantum(_ ikm: Data) -> Data {
        Primitives.hkdfSHA256(ikm: ikm, salt: Data(count: 32), info: postQuantumInfo, length: 32)
    }

    /// Kennung eines Handschlags: das Ephemeral, ohne ein angehängtes
    /// ML-KEM-Chiffrat. Damit bleibt die Liste angenommener Handschläge klein.
    public static func handshakeId(_ payload: JSONObject) -> String? {
        guard let ek = payload["ek"]?.stringValue else { return nil }
        guard let raw = Data(base64: ek), raw.count > 32 else { return ek }
        return raw.prefix(32).detached.base64
    }

    /// Trägt die Nachricht einen Handschlag mit ML-KEM?
    public static func isPostQuantum(_ payload: JSONObject) -> Bool {
        payload["ek"]?.stringValue.flatMap(Data.init(base64:))?.count == 32 + PostQuantum.ciphertextLength
    }
}
