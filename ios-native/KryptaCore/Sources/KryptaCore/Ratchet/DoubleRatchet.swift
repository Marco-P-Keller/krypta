import Foundation

public enum RatchetError: Error, Equatable {
    case tooManySkipped
    case missingChainKey
    case missingRemoteKey
}

/// Signal Double Ratchet — dieselbe Konstruktion wie security/ratchet/double_ratchet.dart.
///
/// X25519-DH, HKDF-SHA256 (Info "KryptaDoubleRatchet-v1"), HMAC-SHA256 für
/// die Kette (0x01 → Nachrichtenschlüssel, 0x02 → nächste Kette),
/// XChaCha20-Poly1305 mit AAD = associatedData ‖ Kopf.
public enum DoubleRatchet {
    /// Höchstens so viele Nachrichten dürfen übersprungen werden.
    public static let maxSkip = 200
    /// Nachholschlüssel verfallen nach sieben Tagen (Vorwärtsgeheimnis).
    public static let maxSkipAge: TimeInterval = 7 * 24 * 3600

    // MARK: Sitzungsbeginn

    /// Als Absender der ersten Nachricht (Alice).
    public static func initAsSender(sharedSecret: Data, recipientRatchetPublicKey: Data) throws -> RatchetState {
        let dh = KeyPair.generate()
        var dhOut = try Primitives.dh(privateKey: dh.privateKey, publicKey: recipientRatchetPublicKey)
        defer { dhOut.zero() }
        let (rootKey, chainKey) = kdfRootKey(sharedSecret, dhOut)
        return RatchetState(
            rootKey: rootKey,
            sendingChainKey: chainKey,
            dhSendingPublic: dh.publicKey,
            dhSendingPrivate: dh.privateKey,
            dhReceivingPublic: recipientRatchetPublicKey
        )
    }

    /// Als Empfänger der ersten Nachricht (Bob). Das Ratchet-Paar ist der
    /// signierte Vorabschlüssel — oder die Identität im Rückfallweg.
    public static func initAsReceiver(sharedSecret: Data, ratchetPublicKey: Data, ratchetPrivateKey: Data) -> RatchetState {
        RatchetState(rootKey: sharedSecret, dhSendingPublic: ratchetPublicKey, dhSendingPrivate: ratchetPrivateKey)
    }

    // MARK: Verschlüsseln

    public static func encrypt(state: RatchetState, plaintext: Data, associatedData: Data) throws -> (RatchetState, RatchetMessage) {
        var s = state
        if s.sendingChainKey == nil {
            s = try dhRatchetSend(s)
        }
        guard let chainKey = s.sendingChainKey else { throw RatchetError.missingChainKey }
        var (nextChainKey, messageKey) = kdfChainKey(chainKey)
        defer { messageKey.zero() }

        let header = RatchetHeader(
            dhPublicKey: s.dhSendingPublic,
            messageNumber: s.sendMessageNumber,
            previousChainLength: s.previousChainLength
        )
        let box = try Primitives.xchachaSeal(plaintext, key: messageKey, aad: associatedData + header.aadBytes)

        s.sendingChainKey = nextChainKey
        s.sendMessageNumber += 1
        nextChainKey.zero()
        return (s, RatchetMessage(
            header: header,
            ciphertext: EncryptedRatchetMessage(ciphertext: box.ciphertext, nonce: box.nonce, mac: box.mac)
        ))
    }

    // MARK: Entschlüsseln

    /// Gibt den neuen Zustand erst zurück, wenn die Nachricht authentisch
    /// ist. Scheitert irgendetwas, bleibt der übergebene Zustand gültig.
    public static func decrypt(state: RatchetState, message: RatchetMessage, associatedData: Data, now: Date = Date()) throws -> (RatchetState, Data) {
        var s = pruneExpiredSkippedKeys(state, now: now)
        let header = message.header
        let ad = associatedData + header.aadBytes

        let skippedKey = "\(header.dhPublicKey.base64):\(header.messageNumber)"
        if var mk = s.skippedMessageKeys[skippedKey] {
            defer { mk.zero() }
            let plaintext = try open(message.ciphertext, key: mk, aad: ad)
            s.skippedMessageKeys.removeValue(forKey: skippedKey)
            s.skippedKeyTimestamps.removeValue(forKey: skippedKey)
            return (s, plaintext)
        }

        let needsDhStep = s.dhReceivingPublic.map { !header.dhPublicKey.constantTimeEquals($0) } ?? true
        if needsDhStep {
            s = try skipMessageKeys(s, until: header.previousChainLength, now: now)
            s = try dhRatchetReceive(s, remotePublicKey: header.dhPublicKey)
        }
        s = try skipMessageKeys(s, until: header.messageNumber, now: now)

        guard let chainKey = s.receivingChainKey else { throw RatchetError.missingChainKey }
        var (nextChainKey, messageKey) = kdfChainKey(chainKey)
        defer { messageKey.zero() }
        s.receivingChainKey = nextChainKey
        s.receiveMessageNumber += 1
        nextChainKey.zero()

        let plaintext = try open(message.ciphertext, key: messageKey, aad: ad)
        return (s, plaintext)
    }

    // MARK: DH-Schritte

    static func dhRatchetSend(_ state: RatchetState) throws -> RatchetState {
        guard let remote = state.dhReceivingPublic else { throw RatchetError.missingRemoteKey }
        var s = state
        let kp = KeyPair.generate()
        var dhOut = try Primitives.dh(privateKey: kp.privateKey, publicKey: remote)
        defer { dhOut.zero() }
        let (rootKey, chainKey) = kdfRootKey(s.rootKey, dhOut)
        s.rootKey = rootKey
        s.sendingChainKey = chainKey
        s.dhSendingPublic = kp.publicKey
        s.dhSendingPrivate = kp.privateKey
        s.previousChainLength = s.sendMessageNumber
        s.sendMessageNumber = 0
        return s
    }

    static func dhRatchetReceive(_ state: RatchetState, remotePublicKey: Data) throws -> RatchetState {
        var s = state
        var dhOut1 = try Primitives.dh(privateKey: s.dhSendingPrivate, publicKey: remotePublicKey)
        defer { dhOut1.zero() }
        let (rk1, receivingChainKey) = kdfRootKey(s.rootKey, dhOut1)

        let kp = KeyPair.generate()
        var dhOut2 = try Primitives.dh(privateKey: kp.privateKey, publicKey: remotePublicKey)
        defer { dhOut2.zero() }
        let (rk2, sendingChainKey) = kdfRootKey(rk1, dhOut2)

        s.rootKey = rk2
        s.receivingChainKey = receivingChainKey
        s.sendingChainKey = sendingChainKey
        s.dhSendingPublic = kp.publicKey
        s.dhSendingPrivate = kp.privateKey
        s.dhReceivingPublic = remotePublicKey.detached
        s.previousChainLength = s.sendMessageNumber
        s.sendMessageNumber = 0
        s.receiveMessageNumber = 0
        return s
    }

    /// Legt Nachholschlüssel bis `until` an; bei mehr als `maxSkip`
    /// Einträgen fliegt der älteste raus.
    static func skipMessageKeys(_ state: RatchetState, until: Int, now: Date) throws -> RatchetState {
        if state.receiveMessageNumber + maxSkip < until { throw RatchetError.tooManySkipped }
        guard state.receivingChainKey != nil, let remote = state.dhReceivingPublic else { return state }
        var s = state
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        while s.receiveMessageNumber < until {
            let (next, mk) = kdfChainKey(s.receivingChainKey!)
            let key = "\(remote.base64):\(s.receiveMessageNumber)"
            s.skippedMessageKeys[key] = mk
            s.skippedKeyTimestamps[key] = nowMs
            while s.skippedMessageKeys.count > maxSkip {
                guard let oldest = s.skippedKeyTimestamps.min(by: { $0.value < $1.value })?.key else { break }
                s.skippedMessageKeys.removeValue(forKey: oldest)
                s.skippedKeyTimestamps.removeValue(forKey: oldest)
            }
            s.receivingChainKey = next
            s.receiveMessageNumber += 1
        }
        return s
    }

    static func pruneExpiredSkippedKeys(_ state: RatchetState, now: Date) -> RatchetState {
        guard !state.skippedKeyTimestamps.isEmpty else { return state }
        let cutoff = Int((now.timeIntervalSince1970 - maxSkipAge) * 1000)
        var s = state
        for (key, ts) in state.skippedKeyTimestamps where ts < cutoff {
            s.skippedMessageKeys.removeValue(forKey: key)
            s.skippedKeyTimestamps.removeValue(forKey: key)
        }
        return s
    }

    // MARK: KDFs

    /// KDF_RK: HKDF-SHA256(salt = rk, ikm = dh) → (neuer rk, ck).
    static func kdfRootKey(_ rootKey: Data, _ dhOutput: Data) -> (Data, Data) {
        var out = Primitives.hkdfSHA256(ikm: dhOutput, salt: rootKey, info: "KryptaDoubleRatchet-v1".utf8Data, length: 64)
        defer { out.zero() }
        return (Data(out.prefix(32)), Data(out.suffix(32)))
    }

    /// KDF_CK: HMAC(ck, 0x02) → nächste Kette, HMAC(ck, 0x01) → Nachrichtenschlüssel.
    static func kdfChainKey(_ chainKey: Data) -> (next: Data, messageKey: Data) {
        (Primitives.hmacSHA256(key: chainKey, message: Data([0x02])),
         Primitives.hmacSHA256(key: chainKey, message: Data([0x01])))
    }

    private static func open(_ msg: EncryptedRatchetMessage, key: Data, aad: Data) throws -> Data {
        try Primitives.xchachaOpen(.init(ciphertext: msg.ciphertext, nonce: msg.nonce, mac: msg.mac), key: key, aad: aad)
    }
}
