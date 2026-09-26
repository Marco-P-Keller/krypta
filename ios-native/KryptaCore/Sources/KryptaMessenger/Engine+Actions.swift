import Foundation
import KryptaCore

extension MessengerEngine {
    // MARK: - Kontakte hinzufügen

    /// Über die Kennung — addContact. Legt eine ausgehende Anfrage an.
    public func addContact(id rawId: String) async -> AddContactResult {
        let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != userId else { return .isSelf }
        guard QRPayload.isValidUserId(id) else { return .invalidId }
        guard let keyB64 = try? await relay.publicKey(uid: id), let key = Data(base64: keyB64), key.count == 32 else {
            return .notFound
        }

        if let existing = contact(id) {
            let moved = ContactRequestPolicy.afterLocalAdd(existing)
            let stateChanged = moved.requestState != existing.requestState
            if stateChanged { updateContact(id) { $0 = moved } }

            let sameKey = existing.publicKey.base64 == keyB64
            // Neu hinzufügen heißt: frischer Handschlag (SessionResetPolicy).
            let freshHandshake = sameKey && !existing.isBlocked
            if freshHandshake, let now = contact(id) {
                discardSessions(contactId: id)
                await sendRequest(to: now, preverifiedKey: keyB64)
            }
            if stateChanged, existing.requestState == .incoming, moved.requestState == .established,
               let chat = chat(forContact: id), let now = contact(id) {
                await sendControl(chatId: chat.id, contact: now, type: "accepted", messageId: UUID().uuidString.lowercased())
            }
            if !sameKey {
                updateContact(id) { $0.markKeyChanged(newKey: key) }
                invalidateHmacKey(id)
                discardSessions(contactId: id)
            }
            return contact(id).map(AddContactResult.added) ?? .notFound
        }

        let contact = Contact(id: id, publicKey: key, requestState: .outgoing)
        contacts.append(contact)
        saveContacts()
        await sendRequest(to: contact, preverifiedKey: keyB64)
        return .added(self.contact(id) ?? contact)
    }

    /// Über den QR-Code — addContactFromQr. Der Schlüssel im Code ist der
    /// Anker; weicht der Server ab, gilt der Code, und der Kontakt ist gesperrt.
    public func addContact(qr: QRPayload) async -> QRAddResult {
        guard qr.userId != userId else { return .notFound }
        guard let serverB64 = try? await relay.publicKey(uid: qr.userId), let serverKey = Data(base64: serverB64) else {
            return .notFound
        }

        guard serverKey.constantTimeEquals(qr.publicKey) else {
            if contact(qr.userId) != nil {
                updateContact(qr.userId) { $0.markKeyChanged(newKey: qr.publicKey) }
            } else {
                var c = Contact(id: qr.userId, publicKey: qr.publicKey, requestState: .established, trustState: .keyChanged)
                c.firstSeenIdentityKey = qr.publicKey
                contacts.append(c)
                saveContacts()
            }
            invalidateHmacKey(qr.userId)
            discardSessions(contactId: qr.userId)
            return .keyMismatch
        }

        if let existing = contact(qr.userId) {
            var moved = ContactRequestPolicy.afterLocalAdd(existing)
            moved.publicKey = qr.publicKey
            moved.trustState = .verified
            moved.verifiedAt = Date()
            moved.verificationMethod = .qrCode
            moved.verifiedFingerprint = qr.fingerprint
            moved.safetyNumberVersion = SafetyNumber.currentVersion
            moved.previousPublicKey = nil
            updateContact(qr.userId) { $0 = moved }
            if !moved.isBlocked {
                discardSessions(contactId: qr.userId)
                await sendRequest(to: moved, qrToken: qr.requestToken, preverifiedKey: serverB64)
            }
            return .verified(contact(qr.userId) ?? moved)
        }

        var c = Contact(id: qr.userId, publicKey: qr.publicKey, requestState: .outgoing, trustState: .verified)
        c.verifiedAt = Date()
        c.verificationMethod = .qrCode
        c.verifiedFingerprint = qr.fingerprint
        c.safetyNumberVersion = SafetyNumber.currentVersion
        contacts.append(c)
        saveContacts()
        await sendRequest(to: c, qrToken: qr.requestToken, preverifiedKey: serverB64)
        return .verified(contact(qr.userId) ?? c)
    }

    /// Frisches Einmal-Token für den eigenen QR-Code (zehn Minuten, einmal gültig).
    public func issueQRToken() -> String {
        let now = Date()
        qrTokens = qrTokens.filter { now.timeIntervalSince($0.value) < Self.qrTokenLifetime }
        let token = Data.random(count: 18).base64
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        qrTokens[token] = now
        return token
    }

    func consumeQRToken(_ token: String?) -> Bool {
        guard let token, let issued = qrTokens.removeValue(forKey: token) else { return false }
        return Date().timeIntervalSince(issued) < Self.qrTokenLifetime
    }

    // MARK: - Anfragen beantworten

    public func acceptRequest(_ contactId: String) async {
        guard contact(contactId)?.requestState == .incoming else { return }
        updateContact(contactId) { $0.requestState = .established }
        if let chat = chat(forContact: contactId), let c = contact(contactId) {
            await sendControl(chatId: chat.id, contact: c, type: "accepted", messageId: UUID().uuidString.lowercased())
        }
    }

    /// Ablehnen: still — die Gegenseite erfährt nichts.
    public func declineRequest(_ contactId: String) async {
        guard contact(contactId)?.requestState == .incoming else { return }
        updateContact(contactId) { $0.requestState = .declined; $0.declineCount += 1 }
        if let chat = chat(forContact: contactId) { await deleteChat(chat.id, announce: false) }
    }

    /// Eine hängende Anfrage mit frischem Handschlag erneut schicken.
    public func resendRequest(_ contactId: String) async {
        guard let c = contact(contactId) else { return }
        discardSessions(contactId: contactId)
        await sendRequest(to: c)
    }

    // MARK: - Vertrauen

    /// Bestätigt, wenn der verglichene Schlüssel der hinterlegte ist.
    @discardableResult
    public func markVerified(_ contactId: String, method: VerificationMethod = .safetyNumber) -> Bool {
        guard let c = contact(contactId) else { return false }
        let fp = Contact.fullFingerprint(c.publicKey)
        updateContact(contactId) {
            $0.trustState = .verified
            $0.verifiedAt = Date()
            $0.verificationMethod = method
            $0.verifiedFingerprint = fp
            $0.safetyNumberVersion = SafetyNumber.currentVersion
            $0.previousPublicKey = nil
        }
        return true
    }

    /// Den Hinweis auf den alten Schlüssel wegräumen. Senden bleibt
    /// gesperrt, bis der neue Schlüssel bestätigt ist — wie in Dart.
    public func acknowledgeKeyChange(_ contactId: String) {
        updateContact(contactId) { $0.previousPublicKey = nil }
    }

    public func block(_ contactId: String) {
        updateContact(contactId) { c in
            guard c.trustState != .blocked else { return }
            c.trustBeforeBlock = c.trustState
            c.trustState = .blocked
        }
    }

    public func unblock(_ contactId: String) {
        updateContact(contactId) { c in
            guard c.trustState == .blocked else { return }
            c.trustState = c.trustBeforeBlock ?? .unverified
            c.trustBeforeBlock = nil
        }
    }

    public func rename(chatId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chat = chat(chatId) else { return }
        updateChat(chatId) { $0.name = trimmed }
        updateContact(chat.recipientId) { $0.displayName = trimmed }
    }

    // MARK: - Lesen

    /// Ein Chat ist offen: alles darin gilt als gelesen.
    public func openChat(_ chatId: String) {
        activeChatId = chatId
        markChatRead(chatId)
    }

    /// Chat verlassen: was „nach dem Ansehen" gehen sollte, geht jetzt.
    public func closeChat(_ chatId: String) async {
        if activeChatId == chatId { activeChatId = nil }
        await burnRead(chatId)
    }

    public func setForeground(_ foreground: Bool) async {
        isForeground = foreground
        if foreground {
            if let chat = activeChatId { markChatRead(chat) }
        } else if let chat = activeChatId {
            await burnRead(chat)
        }
    }

    func markChatRead(_ chatId: String) {
        let now = Date()
        var fresh: [Message] = []
        for i in messages[chatId, default: []].indices {
            let m = messages[chatId]![i]
            guard m.senderId != userId, m.readAt == nil else { continue }
            messages[chatId]![i].readAt = now
            messages[chatId]![i].status = .read
            fresh.append(messages[chatId]![i])
        }
        guard !fresh.isEmpty else { return }
        saveMessages(chatId)
        for m in fresh where !m.isSystemEvent {
            sendReadReceipt(chatId: chatId, senderId: m.senderId, messageId: m.id)
        }
    }

    func sendReadReceipt(chatId: String, senderId: String, messageId: String) {
        guard meta.readReceipts, let c = contact(senderId) else { return }
        sendControlLater(chatId: chatId, contact: c, type: "read", messageId: messageId)
    }

    // MARK: - Löschen

    public func deleteForMe(chatId: String, messageId: String) {
        messages[chatId]?.removeAll { $0.id == messageId }
        saveMessages(chatId)
    }

    /// Nur eigene Nachrichten. Die Meldung darf das Löschen nicht aufhalten.
    public func deleteForEveryone(chatId: String, messageId: String) async {
        guard let m = messages[chatId]?.first(where: { $0.id == messageId }), m.senderId == userId else { return }
        if let chat = chat(chatId), let c = contact(chat.recipientId) {
            let timeout = config.announceTimeout
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor [self] in
                    await sendControl(chatId: chatId, contact: c, type: "delete", messageId: messageId)
                }
                group.addTask { try? await Task.sleep(for: .seconds(timeout)) }
                await group.next()
                group.cancelAll()
            }
        }
        deleteForMe(chatId: chatId, messageId: messageId)
    }

    /// Chat leeren: meine Nachrichten gehen auch drüben.
    public func clearChat(_ chatId: String) async {
        let hasMine = messages(in: chatId).contains { $0.senderId == userId }
        if hasMine, let chat = chat(chatId), let c = contact(chat.recipientId) {
            await sendControlBounded(chatId: chatId, contact: c, type: "clearMine")
        }
        messages[chatId] = []
        saveMessages(chatId)
    }

    /// Chat löschen: Meldung, dann weg — mit Sitzung.
    public func deleteChat(_ chatId: String, announce: Bool = true) async {
        guard deletingChats.insert(chatId).inserted else { return }
        defer { deletingChats.remove(chatId) }
        if announce, ratchets[chatId] != nil, let chat = chat(chatId), let c = contact(chat.recipientId), !c.isGone {
            await sendControlBounded(chatId: chatId, contact: c, type: "chatGone")
        }
        rememberLineage(chatId: chatId)
        chats.removeAll { $0.id == chatId }
        saveChats()
        messages.removeValue(forKey: chatId)
        try? vault.delete("messages.\(chatId)")
        setRatchet(nil, for: chatId)
        pendingHeals = pendingHeals.filter { !$0.key.hasPrefix("\(chatId)|") }
        counters.forget(chatId: chatId)
        saveCounters()
        meta.acceptedEks.removeValue(forKey: chatId)
        meta.pendingBurns.removeAll { $0.chatId == chatId }
        saveMeta()
    }

    // MARK: - Löschfristen

    /// Chat-Regel setzen und der Gegenseite melden.
    public func setChatRule(_ chatId: String, timer: TimeInterval?, afterRead: Bool) async {
        guard let current = chat(chatId) else { return }
        let version = current.ruleVersion + 1
        let id = adoptRule(chatId: chatId, timer: afterRead ? nil : timer, afterRead: afterRead, version: version, from: userId)
        if let c = contact(current.recipientId) {
            await sendControl(chatId: chatId, contact: c, type: SelfDestructPolicy.ruleType(timer: afterRead ? nil : timer, afterRead: afterRead, version: version), messageId: id)
        }
    }

    /// Eine einmalige Nachricht öffnen: der Text kommt genau einmal heraus.
    public func consumeOneTime(chatId: String, messageId: String) -> String? {
        guard let m = messages[chatId]?.first(where: { $0.id == messageId }), m.oneTime, m.senderId != userId,
              let text = m.text, !text.isEmpty else { return nil }
        messages[chatId]?.removeAll { $0.id == messageId }
        saveMessages(chatId)
        reportBurn(chatId: chatId, messageId: messageId)
        return text
    }

    /// Passwort-Nachricht entsperren; fünf Fehlversuche, dann 30 s Pause.
    public enum UnlockResult: Equatable, Sendable { case unlocked, wrongPassword, coolingDown }

    public func unlock(chatId: String, messageId: String, password: String) -> UnlockResult {
        guard let m = messages[chatId]?.first(where: { $0.id == messageId }) else { return .wrongPassword }
        guard m.isPasswordProtected, !m.passwordUnlocked else { return .unlocked }
        guard unlockInFlight.insert(messageId).inserted else { return .coolingDown }
        defer { unlockInFlight.remove(messageId) }

        let now = Date()
        if var attempt = meta.unlockAttempts[messageId], attempt.fails >= Self.maxUnlockAttempts {
            if now.timeIntervalSince(attempt.last) < Self.unlockCooldown { return .coolingDown }
            attempt.fails = 0
            meta.unlockAttempts[messageId] = attempt
        }
        guard let plain = Envelope.decryptWithPassword(m.text ?? "", password: password, aad: "pwd-v1|\(m.senderId)|\(m.recipientId)|\(m.id)") else {
            var attempt = meta.unlockAttempts[messageId] ?? .init(fails: 0, last: now)
            attempt.fails += 1
            attempt.last = now
            meta.unlockAttempts[messageId] = attempt
            saveMeta()
            return .wrongPassword
        }
        meta.unlockAttempts.removeValue(forKey: messageId)
        saveMeta()
        updateMessage(chatId, messageId) { $0.text = plain; $0.passwordUnlocked = true }
        if m.senderId != userId, let c = contact(m.senderId) {
            sendControlLater(chatId: chatId, contact: c, type: "unlock", messageId: messageId)
        }
        return .unlocked
    }

    public func unlockCooldownRemaining(messageId: String) -> TimeInterval {
        guard let a = meta.unlockAttempts[messageId], a.fails >= Self.maxUnlockAttempts else { return 0 }
        return max(0, Self.unlockCooldown - Date().timeIntervalSince(a.last))
    }

    /// Ablaufdatum einer Nachricht für die Anzeige.
    public func deadline(of message: Message) -> Date? {
        SelfDestructPolicy.deadline(message, chat: chat(message.chatId))
    }

    /// Abgelaufenes räumen; mit `includeBurned` auch Gelesenes mit „nach Ansehen".
    func cleanupExpired(includeBurned: Bool) {
        let now = Date()
        for chat in chats {
            guard let list = messages[chat.id], !list.isEmpty else { continue }
            let due = list.filter { m in
                if let d = SelfDestructPolicy.deadline(m, chat: chat), now > d { return true }
                guard includeBurned else { return false }
                return (m.burnAfterRead && m.readAt != nil) || SelfDestructPolicy.afterReadDue(m, ruleAfterRead: chat.deleteAfterRead)
            }
            guard !due.isEmpty else { continue }
            for m in due where SelfDestructPolicy.announceBurn(m, me: userId, chatEphemeral: chat.ruleIsEphemeral) {
                reportBurn(chatId: chat.id, messageId: m.id)
            }
            let ids = Set(due.map(\.id))
            messages[chat.id]?.removeAll { ids.contains($0.id) }
            saveMessages(chat.id)
        }
    }

    /// Gelesenes mit „nach Ansehen" beim Verlassen des Chats räumen.
    func burnRead(_ chatId: String) async {
        guard let chat = chat(chatId), let list = messages[chatId] else { return }
        let due = list.filter { ($0.burnAfterRead && $0.readAt != nil) || SelfDestructPolicy.afterReadDue($0, ruleAfterRead: chat.deleteAfterRead) }
        guard !due.isEmpty else { return }
        for m in due where SelfDestructPolicy.announceBurn(m, me: userId, chatEphemeral: chat.ruleIsEphemeral) {
            reportBurn(chatId: chatId, messageId: m.id)
        }
        let ids = Set(due.map(\.id))
        messages[chatId]?.removeAll { ids.contains($0.id) }
        saveMessages(chatId)
    }

    /// Ablauf melden — wird gespeichert und nachgeholt, bis er raus ist.
    func reportBurn(chatId: String, messageId: String) {
        if !meta.pendingBurns.contains(where: { $0.chatId == chatId && $0.messageId == messageId }) {
            meta.pendingBurns.append(.init(chatId: chatId, messageId: messageId, at: Date()))
            saveMeta()
        }
        scheduleBurn(chatId: chatId, messageId: messageId)
    }

    func scheduleBurn(chatId: String, messageId: String) {
        let key = "\(chatId)|\(messageId)"
        guard burnsInFlight.insert(key).inserted else { return }
        later { [weak self] in
            guard let self else { return }
            defer { self.burnsInFlight.remove(key) }
            guard let chat = self.chat(chatId), let c = self.contact(chat.recipientId) else {
                self.meta.pendingBurns.removeAll { $0.chatId == chatId && $0.messageId == messageId }
                self.saveMeta()
                return
            }
            if await self.sendControl(chatId: chatId, contact: c, type: "burned", messageId: messageId) {
                self.meta.pendingBurns.removeAll { $0.chatId == chatId && $0.messageId == messageId }
                self.saveMeta()
            }
        }
    }

    func retryPendingBurns() {
        let cutoff = Date().addingTimeInterval(-Self.pendingBurnMaxAge)
        let before = meta.pendingBurns.count
        meta.pendingBurns.removeAll { $0.at < cutoff }
        if meta.pendingBurns.count != before { saveMeta() }
        for b in meta.pendingBurns { scheduleBurn(chatId: b.chatId, messageId: b.messageId) }
    }

    // MARK: - Hinweise

    /// Bildschirmfoto oder Aufnahme im offenen Chat melden.
    public func reportSystemEvent(chatId: String, kind: SystemEventKind) async {
        guard kind == .screenshot || kind == .screenRecording, let chat = chat(chatId), let c = contact(chat.recipientId) else { return }
        let id = UUID().uuidString.lowercased()
        appendSystemEvent(chatId: chatId, kind: kind, senderId: userId, messageId: id)
        await sendControl(chatId: chatId, contact: c, type: kind == .screenshot ? "screenshot" : "recording", messageId: id)
    }

    // MARK: - Notfall

    /// Alles löschen: Abschied an alle, Server, Gerät. Keine Rückfrage.
    public func wipeEverything() async {
        stop()
        let timeout = config.announceTimeout
        let targets = chats.compactMap { chat -> (String, Contact)? in
            guard ratchets[chat.id] != nil, let c = contact(chat.recipientId), !c.isGone else { return nil }
            return (chat.id, c)
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [self] in
                for (chatId, c) in targets {
                    _ = await sendControlLocked(chatId: chatId, contact: c, type: "gone", messageId: UUID().uuidString.lowercased())
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)) }
            await group.next()
            group.cancelAll()
        }
        try? await relay.deleteAllUserData(uid: userId)
        for key in hmacKeys.keys { invalidateHmacKey(key) }
        ratchets.removeAll()
        pendingHeals.removeAll()
        pendingHeaders.removeAll()
        contacts.removeAll()
        chats.removeAll()
        messages.removeAll()
        meta = EngineMeta()
        try? vault.wipe()
    }
}
