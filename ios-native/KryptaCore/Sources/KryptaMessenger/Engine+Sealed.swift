import Foundation
import KryptaCore

/// Sealed Sender: Nachrichten ohne Absender auf dem Server.
///
/// Ablauf:
/// 1. Jede Seite hat einen Zustellschlüssel (32 Zufallsbytes). Der Server
///    kennt nur seinen SHA-256 (`sealedAccess/{uid}`).
/// 2. Jede ausgehende Nachricht trägt den eigenen Schlüssel verschlüsselt als
///    `_dk`. Die Flutter-Fassung ignoriert das Feld und schickt keines — so
///    erkennt ein natives Gerät, dass die Gegenseite versiegelt empfangen kann.
/// 3. Wer den Schlüssel der Gegenseite kennt, schickt versiegelt: ohne
///    Anmeldung, Absender und Kennung im Umschlag (`SealedSender`).
/// 4. Lehnt der Server ab (Schlüssel veraltet, Regeln noch nicht ausgerollt),
///    geht die Nachricht wie bisher mit Absender hinaus. Ein Netzfehler
///    dagegen fällt nicht zurück — sonst ließe sich der Absender erzwingen,
///    indem man die versiegelte Verbindung stört.
///
/// Wer gesperrt wird, soll nicht weiter unangemeldet schreiben können: Beim
/// Sperren gibt es einen neuen Schlüssel, und die übrigen Kontakte bekommen
/// ihn mit der nächsten Nachricht.
extension MessengerEngine {
    /// Nach einer Ablehnung eine Weile nicht erneut versuchen.
    static let sealedRetryAfter: TimeInterval = 10 * 60

    /// Der eigene Zustellschlüssel, bei Bedarf neu erzeugt.
    var sealedAccessKey: Data {
        if let key = meta.sealedAccessKey, key.count == SealedSender.accessKeyLength { return key }
        let key = Data.random(count: SealedSender.accessKeyLength)
        meta.sealedAccessKey = key
        saveMeta()
        return key
    }

    func publishSealedAccess() async {
        let hash = SealedSender.accessKeyHash(sealedAccessKey)
        try? await relay.publishSealedAccess(uid: userId, keyHash: hash)
    }

    /// Neuer Schlüssel — der alte taugt ab sofort nicht mehr zum Schreiben.
    func rotateSealedAccessKey() {
        meta.sealedAccessKey = Data.random(count: SealedSender.accessKeyLength)
        saveMeta()
        Task { [weak self] in await self?.publishSealedAccess() }
    }

    /// `_dk` aus einer angenommenen Nachricht übernehmen.
    func learnSealedKey(from contactId: String, inner: JSONObject) {
        guard let b64 = inner["_dk"]?.stringValue, let key = Data(base64: b64),
              key.count == SealedSender.accessKeyLength, contact(contactId)?.sealedKey != key else { return }
        updateContact(contactId) { $0.sealedKey = key }
        sealedDeniedAt.removeValue(forKey: contactId)
    }

    /// Wo die Nachricht auf dem Server liegt und ob versiegelt.
    struct Delivery {
        let docId: String
        let sealed: Bool
    }

    /// Die fertige Nutzlast zum Server bringen — versiegelt, wenn möglich.
    func deliver(to contactId: String, messageId: String, payload: JSONObject) async throws -> Delivery {
        if let current = contact(contactId), let key = current.sealedKey, !sealedPaused(contactId) {
            var inner = payload
            let tag = inner.removeValue(forKey: "nt")?.stringValue
            let envelope = try SealedSender.seal(
                .init(senderId: userId, messageId: messageId, payload: inner),
                recipientId: contactId, recipientIdentity: current.publicKey
            )
            do {
                let docId = try await relay.sendSealed(to: contactId, accessKey: key, envelope: envelope, tag: tag)
                return Delivery(docId: docId, sealed: true)
            } catch RelayError.accessDenied {
                sealedDeniedAt[contactId] = Date()
            }
        }
        let docId = try await relay.send(from: userId, to: contactId, messageId: messageId, payload: payload)
        return Delivery(docId: docId, sealed: false)
    }

    func sealedPaused(_ contactId: String) -> Bool {
        guard let at = sealedDeniedAt[contactId] else { return false }
        return Date().timeIntervalSince(at) < Self.sealedRetryAfter
    }

    /// Einen versiegelten Umschlag öffnen. `nil`: nicht für mich oder kaputt.
    func unseal(_ envelope: InboxEnvelope) -> InboxEnvelope? {
        guard let blob = envelope.sealed else { return envelope }
        guard let contents = try? SealedSender.open(blob, recipientId: userId, identity: identity),
              QRPayload.isValidUserId(contents.senderId), contents.senderId != userId,
              (8...64).contains(contents.messageId.count) else { return nil }
        return InboxEnvelope(docId: envelope.docId, senderId: contents.senderId, messageId: contents.messageId, payload: contents.payload)
    }

    // MARK: - Post-Quanten

    /// Die Gegenseite kann ML-KEM: ab jetzt kein Handschlag mehr ohne.
    /// Nur, wenn dieses Gerät es selbst kann — sonst sperrten wir uns aus.
    func notePostQuantum(_ contactId: String) {
        guard PostQuantum.isAvailable, contact(contactId)?.postQuantum != true else { return }
        updateContact(contactId) { $0.postQuantum = true }
    }

    func requiresPostQuantum(_ contact: Contact) -> Bool {
        PostQuantum.isAvailable && contact.postQuantum == true
    }
}
