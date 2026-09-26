import Foundation
import KryptaCore

/// Key Transparency — verifyContactTransparency, _processTransparencyGossip
/// und KeyManager._publishKeyCommitment der Flutter-Fassung.
///
/// Jeder veröffentlicht eine signierte, verkettete Liste seiner
/// Identitätsschlüssel. Die Engine prüft die Kette jedes Kontakts gegen den
/// Schlüssel, den sie für ihn kennt, und tauscht in jeder Nachricht den
/// Kopf der Kette aus (`_kt`). Zeigt der Server zwei Leuten verschiedene
/// Ketten, fällt das beim nächsten Nachrichtenwechsel auf.
extension MessengerEngine {
    func saveTransparency() {
        let map: JSONObject = transparency.mapValues { JSONValue.object($0.json) }
        guard let text = try? map.jsonString() else { return }
        try? vault.save(Data(text.utf8), slot: "kt")
    }

    func loadTransparency() {
        guard let data = try? vault.load("kt"), let map = try? JSONObject.parse(String(decoding: data, as: UTF8.self)) else { return }
        transparency = map.compactMapValues { $0.objectValue.flatMap { try? TransparencyChain(json: $0) } }
    }

    /// Kette eines Kontakts, wie dieses Gerät sie geprüft hat.
    public func transparencyChain(_ userId: String) -> TransparencyChain? { transparency[userId] }

    public func transparencyFingerprint(_ userId: String) -> String? {
        transparency[userId].flatMap(TransparencyGossip.fingerprint)
    }

    // MARK: - Eigene Kette

    /// Beim Start: die eigene Kette mit dem Server abgleichen.
    ///
    /// Liegt lokal nichts vor (neues Gerät, Übernahme aus Flutter), wird
    /// zuerst die Kette vom Server übernommen, sofern sie sich prüfen lässt —
    /// sonst entstünde eine zweite Epoche 0, und jeder Kontakt sähe beim
    /// Vergleich einen Widerspruch, den es gar nicht gibt. Erst wenn der Kopf
    /// nicht den eigenen Schlüssel nennt, kommt ein neuer Eintrag dazu.
    func syncOwnTransparency() async {
        var chain = transparency[userId] ?? TransparencyChain()
        guard let remote = try? await relay.keyCommitments(uid: userId, since: chain.latestEpoch >= 0 ? chain.latestEpoch : nil) else { return }
        for map in remote {
            guard let c = try? KeyCommitment(json: map) else { break }
            if chain.verifyAndAppend(c, expectedPublicKey: nil) != .valid { break }
        }
        let serverEpoch = max(chain.latestEpoch, remote.compactMap { $0["e"]?.intValue }.max() ?? -1)

        if chain.head?.identityPublicKey != identity.publicKey {
            // Nur anhängen, wenn wir den Server-Kopf kennen — sonst liefe die
            // neue Epoche an einer Stelle an, die schon belegt ist.
            guard chain.latestEpoch == serverEpoch,
                  let c = try? KeyCommitment.create(epoch: chain.latestEpoch + 1, identity: identity, previousHash: chain.headHash),
                  chain.verifyAndAppend(c, expectedPublicKey: identity.publicKey) == .valid else { return }
        }
        transparency[userId] = chain
        saveTransparency()

        // Was der Server noch nicht hat, nachreichen.
        for c in chain.entries where c.epoch > serverEpoch {
            try? await relay.publishKeyCommitment(uid: userId, commitment: c.json, epoch: c.epoch)
        }
    }

    // MARK: - Kontakte

    /// Neue Einträge eines Kontakts holen und prüfen. Fail-closed: was nicht
    /// passt, markiert den Kontakt als nicht geprüft.
    public func verifyTransparency(_ contactId: String) async {
        guard let contact = contact(contactId) else { return }
        var chain = transparency[contactId] ?? TransparencyChain()
        let since = chain.latestEpoch >= 0 ? chain.latestEpoch : nil
        guard let remote = try? await relay.keyCommitments(uid: contactId, since: since), !remote.isEmpty else { return }
        // Zwischen den awaits kann sich der Schlüssel geändert haben.
        guard let current = self.contact(contactId), current.publicKey == contact.publicKey else { return }

        for map in remote {
            guard let c = try? KeyCommitment(json: map) else { return markTransparency(contactId, ok: false) }
            switch chain.verifyAndAppend(c, expectedPublicKey: contact.publicKey) {
            case .valid:
                continue
            case .epochViolation:
                // Schon gesehene Epoche: gleicher Hash ist harmlos, ein
                // anderer heißt, dass der Server zwei Ketten ausliefert.
                if let mine = chain.entry(at: c.epoch), !mine.commitHash.constantTimeEquals(c.commitHash) {
                    return markTransparency(contactId, ok: false)
                }
            default:
                return markTransparency(contactId, ok: false)
            }
        }
        transparency[contactId] = chain
        saveTransparency()
        markTransparency(contactId, ok: true, epoch: chain.latestEpoch)
    }

    func markTransparency(_ contactId: String, ok: Bool, epoch: Int? = nil) {
        updateContact(contactId) { c in
            // Einmal aufgefallen, bleibt es aufgefallen — bis der Kontakt neu
            // bestätigt wird.
            if c.transparencyVerified == false && ok { return }
            c.transparencyVerified = ok
            if let epoch { c.lastVerifiedEpoch = epoch }
        }
    }

    /// Nach einer neuen Bestätigung (QR, Sicherheitsnummer) wird die Kette
    /// neu aufgebaut: der Nutzer hat den Schlüssel selbst verglichen.
    func resetTransparency(_ contactId: String) {
        transparency.removeValue(forKey: contactId)
        saveTransparency()
        updateContact(contactId) { $0.transparencyVerified = nil; $0.lastVerifiedEpoch = nil }
    }

    func verifyAllTransparency() {
        let ids = contacts.filter { !$0.isGone && !$0.isBlocked }.map(\.id)
        Task { [weak self] in
            for id in ids { await self?.verifyTransparency(id) }
        }
    }

    // MARK: - Klatsch

    func gossip(for recipientId: String) -> JSONObject? {
        TransparencyGossip.payload(
            recipient: transparency[recipientId].flatMap { ConsistencyProof(chain: $0, userId: recipientId) },
            own: transparency[userId].flatMap { ConsistencyProof(chain: $0, userId: userId) }
        )
    }

    /// Die Sicht der Gegenseite auf ihre und meine Kette. Ein Widerspruch —
    /// egal in welcher der beiden — heißt: zwischen uns stimmt etwas nicht.
    func processGossip(from senderId: String, inner: JSONObject) {
        guard let map = inner["_kt"]?.objectValue else { return }
        for proof in TransparencyGossip.proofs(in: map) where proof.userId == senderId || proof.userId == userId {
            guard let chain = transparency[proof.userId] else { continue }
            if chain.check(proof) == .splitView { markTransparency(senderId, ok: false) }
        }
    }
}

extension MessengerEngine {
    // MARK: - Mitteilungen

    /// Anhänger für eine Nachricht an `contact` — siehe NotificationTag.
    func notificationTag(for contact: Contact, request: Bool) -> String {
        if request { return NotificationTag.make(key: NotificationTag.requestKey(recipientIdentityPublicKey: contact.publicKey)) }
        guard let key = try? NotificationTag.pairKey(identity: identity, peerIdentityPublicKey: contact.publicKey, ownId: userId, peerId: contact.id) else {
            return NotificationTag.quiet
        }
        return NotificationTag.make(key: key)
    }

    /// Was die Notification Service Extension braucht: je Kontakt, der mir
    /// schreiben darf, der Schlüssel und der Name. Blockierte fehlen — ihre
    /// Nachrichten erscheinen nur als „Neue Nachricht".
    public func notificationIndex(showNames: Bool) -> NotificationIndex {
        let entries = contacts.compactMap { c -> NotificationIndex.Entry? in
            guard !c.isBlocked, !c.isGone, c.requestState == .established || c.requestState == .outgoing,
                  let key = try? NotificationTag.pairKey(identity: identity, peerIdentityPublicKey: c.publicKey, ownId: userId, peerId: c.id)
            else { return nil }
            return .init(key: key, name: chat(forContact: c.id)?.name ?? c.displayName)
        }
        return NotificationIndex(entries: entries, requestKey: NotificationTag.requestKey(recipientIdentityPublicKey: identity.publicKey), showNames: showNames)
    }
}
