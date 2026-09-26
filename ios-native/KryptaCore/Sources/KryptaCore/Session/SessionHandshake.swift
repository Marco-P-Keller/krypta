import Foundation

public enum HandshakeError: Error, Equatable {
    /// Das Bündel nennt eine andere Identität als die hinterlegte (KRY-01).
    case identityMismatch
    case invalidSignature
}

/// Ergebnis einer ausgehenden Sitzung. `header` gehört in die erste
/// Nachricht (`ek` + `spkId`, im Rückfallweg `ek` + `ek2`).
public struct OutboundSession: Sendable {
    public let state: RatchetState
    public let header: JSONObject
}

/// X3DH wie security/session/session_handshake_service.dart.
///
/// Immer 3-DH; Einmal-Vorabschlüssel fließen bewusst nicht ein, solange
/// die Gegenseite sie nicht nachbilden kann.
public enum SessionHandshake {
    static let info = "KryptaX3DH-v1".utf8Data

    /// Absenderseite über das veröffentlichte Bündel.
    ///
    /// `pinnedIdentityPublicKey` ist der Schlüssel, den *dieses* Gerät für
    /// den Kontakt kennt. Er ist der Anker; das Bündel kommt vom Server und
    /// darf nicht bestimmen, wer der Kontakt ist.
    public static func outbound(identity: KeyPair, bundle: PreKeyBundle, pinnedIdentityPublicKey: Data) throws -> OutboundSession {
        guard bundle.identityPublicKey.constantTimeEquals(pinnedIdentityPublicKey) else {
            throw HandshakeError.identityMismatch
        }
        guard bundle.hasValidSignature else { throw HandshakeError.invalidSignature }

        var eph = KeyPair.generate()
        defer { eph.privateKey.zero() }
        var dh1 = try Primitives.dh(privateKey: identity.privateKey, publicKey: bundle.signedPreKeyPublic)
        var dh2 = try Primitives.dh(privateKey: eph.privateKey, publicKey: bundle.identityPublicKey)
        var dh3 = try Primitives.dh(privateKey: eph.privateKey, publicKey: bundle.signedPreKeyPublic)
        var secret = derive(dh1 + dh2 + dh3)
        defer { dh1.zero(); dh2.zero(); dh3.zero(); secret.zero() }

        let state = try DoubleRatchet.initAsSender(sharedSecret: secret, recipientRatchetPublicKey: bundle.signedPreKeyPublic)
        return OutboundSession(state: state, header: [
            "ek": .string(eph.publicKey.base64),
            "spkId": .int(bundle.signedPreKeyId),
        ])
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
        ])
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
        now: Date = Date()
    ) throws -> RatchetState {
        let ek = payload["ek"]?.stringValue.flatMap(Data.init(base64:))
        let ek2 = payload["ek2"]?.stringValue.flatMap(Data.init(base64:))
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
        var secret = derive(dh1 + dh2 + dh3)
        defer { dh1.zero(); dh2.zero(); dh3.zero(); secret.zero() }

        return DoubleRatchet.initAsReceiver(
            sharedSecret: secret,
            ratchetPublicKey: ratchetPair.publicKey,
            ratchetPrivateKey: ratchetPair.privateKey
        )
    }

    static func derive(_ ikm: Data) -> Data {
        Primitives.hkdfSHA256(ikm: ikm, salt: Data(count: 32), info: info, length: 32)
    }
}
