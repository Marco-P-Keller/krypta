import Foundation
import KryptaCore

enum SessionFailure: Error {
    case bundleUnavailable
    case noSession
    case identityMismatch
    /// Die Gegenseite hatte ML-KEM, das Bündel jetzt nicht mehr.
    case postQuantumDowngrade
}

extension MessengerEngine {
    // MARK: - Ausgehende Sitzung

    /// Sitzung als Absender aufbauen — _initRatchetAsSender.
    ///
    /// Fail-closed: kann das Bündel nicht geholt werden (Netzfehler), gibt es
    /// keinen Rückfall auf den schwächeren Weg. Nur wenn der Server sagt,
    /// dass es keines gibt, läuft der Rückfallweg über die Identität.
    func initOutboundSession(chatId: String, contact: Contact) async throws {
        let bundleMap: JSONObject?
        do {
            bundleMap = try await relay.preKeyBundle(uid: contact.id)
        } catch {
            throw SessionFailure.bundleUnavailable
        }

        // Hat die Gegenseite schon ML-KEM gezeigt, darf weder ein Bündel ohne
        // noch der Rückfallweg ohne Bündel eine schwächere Sitzung ergeben.
        let requirePQ = requiresPostQuantum(contact)
        let session: OutboundSession
        if let bundleMap {
            let bundle = try PreKeyBundle(json: bundleMap)
            do {
                session = try SessionHandshake.outbound(identity: identity, bundle: bundle, pinnedIdentityPublicKey: contact.publicKey, requirePostQuantum: requirePQ)
            } catch HandshakeError.identityMismatch {
                bundleIdentityMismatch(contact)
                throw SessionFailure.identityMismatch
            } catch HandshakeError.postQuantumMissing {
                throw SessionFailure.postQuantumDowngrade
            }
            if session.isPostQuantum { notePostQuantum(contact.id) }
        } else {
            guard !requirePQ else { throw SessionFailure.postQuantumDowngrade }
            session = try SessionHandshake.outboundFallback(identity: identity, recipientIdentityPublicKey: contact.publicKey)
        }

        let old = ratchets[chatId]
        var state = session.state
        state.sessionId = UUID().uuidString.lowercased()
        state.previousSessionId = old?.sessionId
        state.peerSeenPsids = lineage(chatId: chatId, old: old)
        ratchets[chatId] = state
        pendingHeaders[chatId] = session.header
        saveRatchet(chatId)
    }

    /// Das Bündel nennt eine andere Identität als hinterlegt (KRY-01):
    /// wie ein Schlüsselwechsel behandeln, aber den Bündel-Schlüssel nicht
    /// übernehmen — _buendelIdentitaetPasstNicht.
    func bundleIdentityMismatch(_ contact: Contact) {
        updateContact(contact.id) { $0.markKeyChanged(newKey: nil) }
        invalidateHmacKey(contact.id)
        for chat in chats where chat.recipientId == contact.id {
            setRatchet(nil, for: chat.id)
        }
    }

    // MARK: - Eingehende Sitzung

    func deriveInbound(chatId: String, contact: Contact, payload: JSONObject) throws -> RatchetState {
        var state = try SessionHandshake.inbound(
            identity: identity, preKeys: preKeys,
            senderIdentityPublicKey: contact.publicKey, header: payload,
            requirePostQuantum: requiresPostQuantum(contact)
        )
        let old = ratchets[chatId]
        state.sessionId = UUID().uuidString.lowercased()
        state.previousSessionId = old?.sessionId
        state.peerSeenPsids = lineage(chatId: chatId, old: old)
        return state
    }

    /// Bekannte `_psid` dieses Kontakts: gespeicherte Spur plus die der
    /// alten Sitzung — C5, übersteht das Verwerfen einer Sitzung.
    func lineage(chatId: String, old: RatchetState?) -> Set<String> {
        guard let contactId = chat(chatId)?.recipientId else { return old?.peerSeenPsids ?? [] }
        return Set(meta.psidLineage[contactId] ?? []).union(old?.peerSeenPsids ?? [])
    }

    func rememberLineage(chatId: String) {
        guard let contactId = chat(chatId)?.recipientId, let state = ratchets[chatId] else { return }
        var spur = meta.psidLineage[contactId] ?? []
        for id in state.peerSeenPsids.sorted() where !spur.contains(id) { spur.append(id) }
        if spur.count > Self.maxLineage { spur.removeFirst(spur.count - Self.maxLineage) }
        guard spur != meta.psidLineage[contactId] else { return }
        meta.psidLineage[contactId] = spur
        saveMeta()
    }

    /// Sitzung verwerfen; die nächste Nachricht trägt wieder einen Handschlag.
    func discardSession(chatId: String) {
        rememberLineage(chatId: chatId)
        setRatchet(nil, for: chatId)
        pendingHeals = pendingHeals.filter { !$0.key.hasPrefix("\(chatId)|") }
    }

    func discardSessions(contactId: String) {
        for chat in chats where chat.recipientId == contactId {
            discardSession(chatId: chat.id)
        }
    }

    // MARK: - Verschlüsseln

    /// Innerer Text → Padding → Ratchet. Synchron: zwischen Lesen und
    /// Zurückschreiben des Zustands liegt kein `await`.
    func encrypt(chatId: String, content: String) throws -> JSONObject {
        guard let state = ratchets[chatId] else { throw SessionFailure.noSession }
        let (next, message) = try DoubleRatchet.encrypt(
            state: state, plaintext: Envelope.pad(content.utf8Data), associatedData: userId.utf8Data
        )
        ratchets[chatId] = next
        saveRatchet(chatId)
        var map = message.payloadMap
        if let header = pendingHeaders[chatId] { map.merge(header) { _, new in new } }
        map["v"] = 3
        return map
    }

    /// Erst wenn der Server angenommen hat, ist der Handschlag-Kopf verbraucht.
    func handshakeDelivered(chatId: String) {
        guard pendingHeaders.removeValue(forKey: chatId) != nil else { return }
        saveRatchet(chatId)
    }

    // MARK: - Entschlüsseln

    static func healKey(_ chatId: String, _ messageId: String) -> String { "\(chatId)|\(messageId)" }

    /// Entschlüsselt synchron und gibt den inneren Text zurück.
    ///
    /// Eine neu abgeleitete Sitzung wird nur übernommen, wenn sie die
    /// Nachricht auch entschlüsselt. Scheitert die bestehende Sitzung und die
    /// Nachricht trägt einen neuen Handschlag, wird eine geheilte Sitzung
    /// *vorgemerkt*: sie gilt erst, wenn die Nachricht alle Prüfungen
    /// bestanden hat (finalizeAccepted).
    func decrypt(chatId: String, contact: Contact, payload: JSONObject, messageId: String) throws -> String {
        let message = try RatchetMessage(payload: payload)
        let ad = contact.id.utf8Data

        let result: (RatchetState, Data)
        if let state = ratchets[chatId] {
            do {
                result = try DoubleRatchet.decrypt(state: state, message: message, associatedData: ad)
                ratchets[chatId] = result.0
                saveRatchet(chatId)
            } catch {
                guard let healed = tryHeal(chatId: chatId, contact: contact, payload: payload, message: message, ad: ad) else {
                    throw error
                }
                result = healed
                pendingHeals[Self.healKey(chatId, messageId)] = healed.0
            }
        } else {
            let fresh = try deriveInbound(chatId: chatId, contact: contact, payload: payload)
            result = try DoubleRatchet.decrypt(state: fresh, message: message, associatedData: ad)
            ratchets[chatId] = result.0
            saveRatchet(chatId)
        }

        var padded = result.1
        defer { padded.zero() }
        let plain = try Envelope.unpad(padded)
        return String(decoding: plain, as: UTF8.self)
    }

    /// _tryHealSession: nur mit Kopf, nur mit einem noch nie angenommenen `ek`.
    func tryHeal(chatId: String, contact: Contact, payload: JSONObject, message: RatchetMessage, ad: Data) -> (RatchetState, Data)? {
        guard let ek = SessionHandshake.handshakeId(payload) else { return nil }
        if meta.acceptedEks[chatId]?.contains(ek) == true { return nil }
        guard let fresh = try? deriveInbound(chatId: chatId, contact: contact, payload: payload) else { return nil }
        return try? DoubleRatchet.decrypt(state: fresh, message: message, associatedData: ad)
    }

    /// Commit-Punkt für eine angenommene Nachricht — _finalizeAcceptedMessage.
    /// `false`: Duplikat eines schon übernommenen Neu-Handschlags.
    func finalizeAccepted(chatId: String, messageId: String, payload: JSONObject) -> Bool {
        let ek = SessionHandshake.handshakeId(payload)
        if let pending = pendingHeals.removeValue(forKey: Self.healKey(chatId, messageId)) {
            if let ek, meta.acceptedEks[chatId]?.contains(ek) == true { return false }
            ratchets[chatId] = pending
            pendingHeaders.removeValue(forKey: chatId)
            saveRatchet(chatId)
        }
        if let ek { markAcceptedEk(chatId: chatId, ek: ek) }
        // Ein angenommener Handschlag mit ML-KEM: die Gegenseite kann es.
        if SessionHandshake.isPostQuantum(payload), let contactId = chat(chatId)?.recipientId {
            notePostQuantum(contactId)
        }
        return true
    }

    func discardPendingHeal(chatId: String, messageId: String) {
        pendingHeals.removeValue(forKey: Self.healKey(chatId, messageId))
    }

    func markAcceptedEk(chatId: String, ek: String) {
        var list = meta.acceptedEks[chatId] ?? []
        guard !list.contains(ek) else { return }
        list.append(ek)
        if list.count > Self.maxAcceptedEks { list.removeFirst() }
        meta.acceptedEks[chatId] = list
        saveMeta()
    }

    /// C4/C5: Replay- und Rollback-Prüfung gegen die Sitzung dieser Nachricht.
    func enforceReplay(chatId: String, inner: JSONObject, version: Int, messageId: String) -> Bool {
        let key = Self.healKey(chatId, messageId)
        let pending = pendingHeals[key]
        guard let state = pending ?? ratchets[chatId] else { return true }
        guard let advanced = try? ReplayGuard.validate(state: state, inner: inner, version: version) else { return false }
        guard advanced != state else { return true }
        if pending != nil {
            pendingHeals[key] = advanced
        } else {
            ratchets[chatId] = advanced
            saveRatchet(chatId)
        }
        return true
    }

    // MARK: - Schlüssel für Steuernachrichten

    func controlKey(_ contact: Contact) throws -> Data {
        if let cached = hmacKeys[contact.id] { return cached }
        let key = try ControlMessage.pairKey(identity: identity, peerIdentityPublicKey: contact.publicKey, ownId: userId, peerId: contact.id)
        hmacKeys[contact.id] = key
        return key
    }

    func invalidateHmacKey(_ contactId: String) {
        if var key = hmacKeys.removeValue(forKey: contactId) { key.zero() }
    }
}
