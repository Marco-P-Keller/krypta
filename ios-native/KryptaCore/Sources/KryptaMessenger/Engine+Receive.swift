import Foundation
import KryptaCore

extension MessengerEngine {
    /// Eine Nachricht aus dem Posteingang verarbeiten — _handleInbox.
    ///
    /// Was nicht angenommen wird, wird trotzdem vom Server gelöscht: der
    /// Posteingang ist ein Durchgang, kein Archiv.
    func receive(_ incoming: InboxEnvelope) async {
        defer { purgeFromInbox(incoming.docId) }
        guard isRunning else { return }
        // Versiegelt: Absender und Kennung stehen erst nach dem Öffnen fest.
        guard let env = unseal(incoming) else { return }

        // Übergroße Nutzlasten gar nicht erst entschlüsseln.
        guard let size = try? env.payload.jsonString().utf8.count, size <= 65_536 else { return }

        let existing = contact(env.senderId)
        // Von jemandem ohne angenommenen Kontakt kommt genau eine Sache
        // durch: eine Kontaktanfrage ohne Inhalt.
        if existing == nil || existing?.requestState == .incoming || existing?.requestState == .declined {
            await receiveRequest(env, existing: existing)
            return
        }
        guard let contact = existing else { return }

        // Vertrauen — fail-closed.
        if contact.isBlocked || contact.hasKeyChanged { return }
        // TOFU: ein unbestätigter Kontakt behält den zuerst gesehenen Schlüssel.
        if contact.trustState == .unverified, let first = contact.firstSeenIdentityKey, !first.constantTimeEquals(contact.publicKey) { return }

        let chat = chatFor(contact)
        guard !deletingChats.contains(chat.id) else { return }
        if meta.processedIds.contains(env.messageId) || messages(in: chat.id).contains(where: { $0.id == env.messageId }) { return }

        let version = env.payload["v"]?.intValue ?? 1
        guard version >= 2 else { return }

        let plaintext: String
        do {
            plaintext = try decrypt(chatId: chat.id, contact: contact, payload: env.payload, messageId: env.messageId)
        } catch {
            return
        }

        let inner: JSONObject
        let content: String
        if version >= 3 {
            guard let parsed = try? JSONObject.parse(plaintext) else {
                discardPendingHeal(chatId: chat.id, messageId: env.messageId)
                return
            }
            inner = parsed
            content = parsed["_t"]?.stringValue ?? ""
        } else {
            // v2: Metadaten neben den Ratchet-Feldern, für den Server sichtbar.
            inner = env.payload
            content = plaintext
        }

        // Steuernachrichten nur aus v3 — in v2 wäre `_ctrl` vom Server fälschbar.
        if version >= 3, inner["_ctrl"] != nil {
            if await processControl(chatId: chat.id, contact: contact, inner: inner) {
                _ = finalizeAccepted(chatId: chat.id, messageId: env.messageId, payload: env.payload)
                learnSealedKey(from: contact.id, inner: inner)
            } else {
                discardPendingHeal(chatId: chat.id, messageId: env.messageId)
            }
            return
        }

        // Sealed Sender: die maßgebliche Absenderkennung liegt in der Verschlüsselung.
        guard inner["_sid"]?.stringValue == env.senderId else {
            discardPendingHeal(chatId: chat.id, messageId: env.messageId)
            return
        }

        // Anfrage von jemandem, den ich selbst angefragt habe: beide sind einverstanden.
        if inner["_rq"] == 1 {
            let state = ContactRequestPolicy.stateAfterIncoming(contact)
            if state != contact.requestState { updateContact(contact.id) { $0.requestState = state } }
            _ = finalizeAccepted(chatId: chat.id, messageId: env.messageId, payload: env.payload)
            learnSealedKey(from: contact.id, inner: inner)
            markProcessed(env.messageId)
            return
        }

        guard enforceReplay(chatId: chat.id, inner: inner, version: version, messageId: env.messageId) else {
            discardPendingHeal(chatId: chat.id, messageId: env.messageId)
            return
        }
        guard finalizeAccepted(chatId: chat.id, messageId: env.messageId, payload: env.payload) else { return }
        processGossip(from: env.senderId, inner: inner)
        learnSealedKey(from: env.senderId, inner: inner)

        let now = Date()
        let isRead = activeChatId == chat.id && isForeground
        var m = Message(
            id: env.messageId, chatId: chat.id, senderId: env.senderId, recipientId: userId,
            text: content, timestamp: now, status: isRead ? .read : .delivered
        )
        m.deliveredAt = now
        m.readAt = isRead ? now : nil
        m.selfDestructFromChat = inner["_sdc"] == true
        let sdMs = inner["_sd"]?.intValue ?? inner["sd"]?.intValue
        m.selfDestruct = sdMs.flatMap(SelfDestructPolicy.clamp(ms:))
        m.burnAfterRead = Self.flag(inner, "_bar") || Self.flag(inner, "bar")
        m.oneTime = Self.flag(inner, "_once")
        m.isPasswordProtected = Self.flag(inner, "_pw") || Self.flag(inner, "pw")
        m.passwordUnlocked = !m.isPasswordProtected
        append(m, to: chat.id)
        markProcessed(env.messageId)

        // Zustellung wird immer gemeldet: an ihr hängt der Start jeder Frist.
        sendControlLater(chatId: chat.id, contact: contact, type: "delivered", messageId: env.messageId)
        if isRead { sendReadReceipt(chatId: chat.id, senderId: env.senderId, messageId: env.messageId) }
    }

    /// Dart schreibt Flags als `true`, ältere Fassungen auch als `"true"`.
    static func flag(_ inner: JSONObject, _ key: String) -> Bool {
        inner[key] == true || inner[key] == .string("true")
    }

    // MARK: - Kontaktanfragen

    /// _receiveContactRequest: nur `_rq` ohne Inhalt wird angenommen.
    func receiveRequest(_ env: InboxEnvelope, existing: Contact?) async {
        if ContactRequestPolicy.rejectIncoming(existing: existing, openIncoming: incomingRequests.count) { return }
        guard (env.payload["v"]?.intValue ?? 1) >= 3 else { return }

        var contact: Contact
        if let existing {
            contact = existing
        } else {
            guard QRPayload.isValidUserId(env.senderId),
                  let keyB64 = try? await relay.publicKey(uid: env.senderId),
                  let key = Data(base64: keyB64), key.count == 32 else { return }
            // Zwischen den awaits kann derselbe Absender angelegt worden sein.
            if let raced = self.contact(env.senderId) { contact = raced } else {
                contact = Contact(id: env.senderId, publicKey: key, requestState: .incoming)
            }
        }

        let existingChat = chat(forContact: env.senderId)
        let chatId = existingChat?.id ?? UUID().uuidString.lowercased()

        let plaintext: String
        do {
            plaintext = try decrypt(chatId: chatId, contact: contact, payload: env.payload, messageId: env.messageId)
        } catch {
            discardPendingHeal(chatId: chatId, messageId: env.messageId)
            if existingChat == nil { ratchets.removeValue(forKey: chatId); try? vault.delete("ratchet.\(chatId)") }
            return
        }
        guard let inner = try? JSONObject.parse(plaintext), inner["_sid"]?.stringValue == env.senderId, inner["_rq"] == 1 else {
            // Inhalt von einem unbestätigten Kontakt wird verworfen.
            discardPendingHeal(chatId: chatId, messageId: env.messageId)
            if existingChat == nil { ratchets.removeValue(forKey: chatId); try? vault.delete("ratchet.\(chatId)") }
            return
        }

        // Zeigen heißt Zustimmen: ein gültiges QR-Token macht die Anfrage direkt fest.
        let fromQR = consumeQRToken(inner["_rt"]?.stringValue)
        contact.requestState = fromQR ? .established : ContactRequestPolicy.stateAfterIncoming(existing)
        if let i = contacts.firstIndex(where: { $0.id == contact.id }) { contacts[i] = contact } else { contacts.append(contact) }
        saveContacts()

        if existingChat == nil {
            var chat = Chat(id: chatId, recipientId: contact.id, name: contact.displayName)
            chat.lastActivity = Date()
            chats.append(chat)
            messages[chatId] = []
            saveChats()
            saveRatchet(chatId)
        }
        guard finalizeAccepted(chatId: chatId, messageId: env.messageId, payload: env.payload) else { return }
        learnSealedKey(from: contact.id, inner: inner)
        markProcessed(env.messageId)
        if existing == nil { Task { [weak self] in await self?.verifyTransparency(contact.id) } }

        if contact.requestState == .established {
            await sendControl(chatId: chatId, contact: contact, type: "accepted", messageId: UUID().uuidString.lowercased())
        }
    }

    // MARK: - Steuernachrichten empfangen

    /// Prüft Signatur, Absender, Alter und Zähler, dann wird angewandt.
    /// `true`, wenn die Nachricht echt und frisch war.
    func processControl(chatId: String, contact: Contact, inner: JSONObject) async -> Bool {
        guard let map = inner["_ctrl"]?.objectValue, let ctrl = try? ControlMessage(json: map),
              let key = try? controlKey(contact), ctrl.verify(key: key) else { return false }
        if ctrl.validate(expectedSenderId: contact.id, lastSeenCounter: counters.lastSeen(for: chatId), maxAge: ControlMessagePolicy.maxAge(ctrl.type)) != nil {
            return false
        }
        guard counters.record(ctrl.counter, for: chatId) else { return false }
        saveCounters()

        switch ctrl.type {
        case "delivered": applyDelivered(ctrl.messageId, reportedMs: ctrl.timestamp)
        case "read": applyRead(ctrl.messageId)
        case "delete": applyRemoteDelete(ctrl.messageId)
        case "unlock": applyUnlocked(ctrl.messageId)
        case "accepted":
            if self.contact(contact.id)?.requestState == .outgoing { updateContact(contact.id) { $0.requestState = .established } }
        case "clearMine": applyPeerClear(chatId: chatId, peerId: contact.id)
        case "burned": applyBurned(chatId: chatId, messageId: ctrl.messageId)
        case "chatGone": applyPeerChatGone(chatId: chatId, peerId: contact.id)
        case "gone": applyPeerGone(chatId: chatId, peerId: contact.id)
        case "screenshot": appendSystemEvent(chatId: chatId, kind: .screenshot, senderId: contact.id, messageId: ctrl.messageId)
        case "recording": appendSystemEvent(chatId: chatId, kind: .screenRecording, senderId: contact.id, messageId: ctrl.messageId)
        default:
            if let rule = SelfDestructPolicy.rule(from: ctrl.type), let current = chat(chatId),
               SelfDestructPolicy.adoptForeignRule(mine: current.ruleVersion, theirs: rule.version, myId: userId, theirId: contact.id) {
                adoptRule(chatId: chatId, timer: rule.timer, afterRead: rule.afterRead, version: rule.version, from: contact.id, eventId: ctrl.messageId)
            }
        }
        return true
    }

    /// Zustellung meiner Nachricht; der Zeitpunkt aus fremder Uhr wird gekappt
    /// und nie verschoben, wenn er schon steht.
    func applyDelivered(_ messageId: String, reportedMs: Int) {
        guard let (chatId, i) = locate(messageId), messages[chatId]![i].senderId == userId else { return }
        retractServerCopy(messageId: messageId)
        updateMessage(chatId, messageId) { m in
            if m.deliveredAt == nil {
                m.deliveredAt = SelfDestructPolicy.deliveredAt(reported: Date(timeIntervalSince1970: Double(reportedMs) / 1000), sent: m.timestamp, now: Date())
            }
            if m.status != .read { m.status = .delivered }
        }
    }

    func applyRead(_ messageId: String) {
        retractServerCopy(messageId: messageId)
        guard let (chatId, i) = locate(messageId), messages[chatId]![i].senderId == userId, messages[chatId]![i].status != .read else { return }
        updateMessage(chatId, messageId) {
            $0.status = .read
            $0.readAt = Date()
            if $0.deliveredAt == nil { $0.deliveredAt = $0.timestamp }
        }
    }

    /// Nur Nachrichten der Gegenseite darf sie zurücknehmen.
    func applyRemoteDelete(_ messageId: String) {
        guard let (chatId, i) = locate(messageId), messages[chatId]![i].senderId != userId else { return }
        messages[chatId]!.remove(at: i)
        saveMessages(chatId)
    }

    func applyUnlocked(_ messageId: String) {
        guard let (chatId, i) = locate(messageId), messages[chatId]![i].senderId == userId else { return }
        updateMessage(chatId, messageId) { if $0.isPasswordProtected { $0.passwordUnlocked = true } }
    }

    func applyBurned(chatId: String, messageId: String) {
        guard let m = messages[chatId]?.first(where: { $0.id == messageId }) else { return }
        guard SelfDestructPolicy.acceptBurn(m, me: userId, chatEphemeral: chat(chatId)?.ruleIsEphemeral ?? false) else { return }
        messages[chatId]?.removeAll { $0.id == messageId }
        saveMessages(chatId)
    }

    /// Die Gegenseite hat ihren Chat geleert: ihre Nachrichten gehen auch hier.
    func applyPeerClear(chatId: String, peerId: String) {
        let before = messages[chatId]?.count ?? 0
        messages[chatId]?.removeAll { $0.senderId == peerId && !$0.isSystemEvent }
        guard messages[chatId]?.count != before else { return }
        saveMessages(chatId)
    }

    /// Die Gegenseite hat den Chat weggeworfen: ihre Nachrichten gehen, und
    /// die Sitzung fällt, damit meine nächste Nachricht einen Handschlag trägt.
    func applyPeerChatGone(chatId: String, peerId: String) {
        let now = Date()
        if let last = lastChatGone[peerId], now.timeIntervalSince(last) < Self.chatGoneBrake { return }
        lastChatGone[peerId] = now
        applyPeerClear(chatId: chatId, peerId: peerId)
        discardSession(chatId: chatId)
    }

    func applyPeerGone(chatId: String, peerId: String) {
        applyPeerClear(chatId: chatId, peerId: peerId)
        updateContact(peerId) { c in
            guard !c.isGone else { return }
            c.isGone = true
            c.goneAt = Date()
        }
        appendSystemEvent(chatId: chatId, kind: .accountDeleted, senderId: peerId, messageId: UUID().uuidString.lowercased())
    }

    func appendSystemEvent(chatId: String, kind: SystemEventKind, senderId: String, messageId: String, timer: TimeInterval? = nil) {
        guard !meta.processedIds.contains(messageId), !messages(in: chatId).contains(where: { $0.id == messageId }) else { return }
        let now = Date()
        let read = senderId == userId || (activeChatId == chatId && isForeground)
        let recipient = senderId == userId ? (chat(chatId)?.recipientId ?? "") : userId
        var m = Message(id: messageId, chatId: chatId, senderId: senderId, recipientId: recipient, text: nil, timestamp: now, status: .delivered)
        m.readAt = read ? now : nil
        m.selfDestruct = timer
        m.systemEvent = kind
        append(m, to: chatId)
    }

    /// Die Chat-Regel übernehmen (eigene oder fremde) und einen Hinweis setzen.
    @discardableResult
    func adoptRule(chatId: String, timer: TimeInterval?, afterRead: Bool, version: Int, from senderId: String, eventId: String? = nil) -> String {
        updateChat(chatId) { c in
            c.timer = timer
            c.timerSetAt = timer == nil ? nil : Date()
            c.deleteAfterRead = afterRead
            c.ruleVersion = version
        }
        let id = eventId ?? UUID().uuidString.lowercased()
        appendSystemEvent(chatId: chatId, kind: afterRead ? .selfDestructAfterRead : .selfDestructChanged, senderId: senderId, messageId: id, timer: timer)
        return id
    }
}
