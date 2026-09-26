import Foundation
import KryptaCore

extension MessengerEngine {
    /// Eine Textnachricht senden.
    ///
    /// Die Blase steht sofort; scheitert etwas, bleibt sie mit `failed`
    /// stehen, statt still zu verschwinden.
    public func send(chatId: String, text: String, options: SendOptions = .plain) async {
        await enqueue(chatId) { [self] in
            await sendLocked(chatId: chatId, text: text, options: options, asRequest: false, qrToken: nil, preverifiedKey: nil)
        }
    }

    /// Eine Kontaktanfrage: trägt keinen Text, nur `_rq` (und `_rt` aus dem QR-Code).
    func sendRequest(to contact: Contact, qrToken: String? = nil, preverifiedKey: String? = nil) async {
        let chat = chatFor(contact)
        await enqueue(chat.id) { [self] in
            await sendLocked(chatId: chat.id, text: "", options: .plain, asRequest: true, qrToken: qrToken, preverifiedKey: preverifiedKey)
        }
    }

    func sendLocked(chatId: String, text: String, options: SendOptions, asRequest: Bool, qrToken: String?, preverifiedKey: String?) async {
        guard !deletingChats.contains(chatId), let chat = chat(chatId), let contact = contact(chat.recipientId) else { return }

        // Vertrauensprüfung — fail-closed. Eine Anfrage darf an einer
        // offenen Anfrage vorbei, aber nie an einer Sperre.
        if asRequest {
            if contact.isBlocked { return }
        } else if sendBlockReason(contact) != nil {
            return
        }

        let messageId = UUID().uuidString.lowercased()
        let now = Date()
        let password = options.password.flatMap { $0.isEmpty ? nil : $0 }
        let oneTime = options.oneTime

        if !asRequest {
            var m = Message(
                id: messageId, chatId: chatId, senderId: userId, recipientId: contact.id,
                // Eine einmalige Nachricht behält der Absender nicht.
                text: oneTime ? nil : text, timestamp: now, status: .sending
            )
            m.selfDestruct = options.selfDestruct
            m.selfDestructFromChat = options.fromChatRule
            m.burnAfterRead = options.burnAfterRead && !oneTime
            m.oneTime = oneTime
            m.isPasswordProtected = password != nil
            m.passwordUnlocked = password == nil
            append(m, to: chatId)
        }

        func fail() {
            if !asRequest { updateMessage(chatId, messageId) { $0.status = .failed } }
        }

        // Hat der Server einen anderen Schlüssel als ich? Dann nichts senden,
        // sondern den Schlüsselwechsel auslösen.
        if preverifiedKey == nil || preverifiedKey != contact.publicKey.base64 {
            do {
                if let serverKey = try await relay.publicKey(uid: contact.id), serverKey != contact.publicKey.base64 {
                    // Nicht hier drin abwarten: der Schlüsselwechsel sendet
                    // selbst an diesen Chat und stünde hinter uns in der Schlange.
                    Task { [weak self] in _ = await self?.addContact(id: contact.id) }
                    return fail()
                }
            } catch {
                return fail()
            }
        }

        var content = text
        if let password {
            // An Absender, Empfänger und Nachricht gebunden (H4-Crypto).
            guard let blob = try? Envelope.encryptWithPassword(text, password: password, aad: "pwd-v1|\(userId)|\(contact.id)|\(messageId)") else {
                return fail()
            }
            content = blob
        }

        do {
            if ratchets[chatId] == nil {
                try await initOutboundSession(chatId: chatId, contact: contact)
            }
            guard let state = ratchets[chatId] else { return fail() }

            // v3: alle Metadaten innerhalb der Verschlüsselung.
            var inner: JSONObject = [
                "_t": .string(content),
                "_sid": .string(userId),
                "_seq": .int(state.globalSendSeqNo),
            ]
            if asRequest {
                inner["_rq"] = 1
                if let qrToken { inner["_rt"] = .string(qrToken) }
            }
            if state.globalSendSeqNo == 0, let psid = state.previousSessionId { inner["_psid"] = .string(psid) }
            if let sd = options.selfDestruct { inner["_sd"] = .int(Int(sd * 1000)) }
            if options.fromChatRule { inner["_sdc"] = true }
            if options.burnAfterRead && !oneTime { inner["_bar"] = true }
            if oneTime { inner["_once"] = true }
            if password != nil { inner["_pw"] = true }
            if !asRequest, let kt = gossip(for: contact.id) { inner["_kt"] = .object(kt) }

            var payload = try encrypt(chatId: chatId, content: try inner.jsonString())
            if let tag = notificationTag(for: contact, request: asRequest) { payload["nt"] = .string(tag) }
            ratchets[chatId]?.globalSendSeqNo += 1
            saveRatchet(chatId)

            try await relay.send(from: userId, to: contact.id, messageId: messageId, payload: payload)
            handshakeDelivered(chatId: chatId)
            if !asRequest { updateMessage(chatId, messageId) { if $0.status == .sending { $0.status = .sent } } }
        } catch SessionFailure.identityMismatch {
            fail()
        } catch {
            fail()
        }
    }

    /// Warum an diesen Kontakt nichts rausgeht — _validateSendPermission.
    func sendBlockReason(_ c: Contact) -> String? {
        if c.isGone { return "gone" }
        if c.isBlocked { return "blocked" }
        if c.hasKeyChanged { return "key_changed" }
        if !c.canSendMessages { return "trust_insufficient" }
        return nil
    }

    /// Eine gescheiterte Nachricht erneut senden.
    public func resend(chatId: String, messageId: String) async {
        guard let m = messages[chatId]?.first(where: { $0.id == messageId }),
              m.status == .failed, m.senderId == userId, let text = m.text, !m.isPasswordProtected else { return }
        messages[chatId]?.removeAll { $0.id == messageId }
        saveMessages(chatId)
        await send(chatId: chatId, text: text, options: SendOptions(selfDestruct: m.selfDestruct, fromChatRule: m.selfDestructFromChat, burnAfterRead: m.burnAfterRead))
    }

    // MARK: - Steuernachrichten

    /// Signierte Steuernachricht durch denselben verschlüsselten Kanal.
    /// `false`: nicht gesendet (keine Sitzung, Kontakt gesperrt).
    @discardableResult
    func sendControl(chatId: String, contact: Contact, type: String, messageId: String) async -> Bool {
        var sent = false
        await enqueue(chatId) { [self] in
            sent = await sendControlLocked(chatId: chatId, contact: contact, type: type, messageId: messageId)
        }
        return sent
    }

    func sendControlLocked(chatId: String, contact: Contact, type: String, messageId: String) async -> Bool {
        guard let current = self.contact(contact.id), sendBlockReason(current) == nil,
              ratchets[chatId] != nil,
              let key = try? controlKey(current) else { return false }
        let counter = counters.next(for: chatId)
        saveCounters()
        let ctrl = ControlMessage.create(type: type, chatId: chatId, messageId: messageId, senderId: userId, counter: counter, key: key)
        let inner: JSONObject = ["_ctrl": .object(ctrl.json), "_sid": .string(userId)]
        do {
            var payload = try encrypt(chatId: chatId, content: try inner.jsonString())
            // Steuernachrichten lösen keine Mitteilung aus.
            payload["nt"] = .string(NotificationTag.quiet)
            try await relay.send(from: userId, to: current.id, messageId: UUID().uuidString.lowercased(), payload: payload)
            handshakeDelivered(chatId: chatId)
            return true
        } catch {
            return false
        }
    }

    /// Mit Streuung melden (Zustellung, Lesen, Entsperren).
    func sendControlLater(chatId: String, contact: Contact, type: String, messageId: String) {
        later { [weak self] in
            await self?.sendControl(chatId: chatId, contact: contact, type: type, messageId: messageId)
        }
    }

    /// Meldungen beim Löschen dürfen den Vorgang nicht aufhalten.
    func sendControlBounded(chatId: String, contact: Contact, type: String) async {
        let timeout = config.announceTimeout
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [self] in
                await sendControl(chatId: chatId, contact: contact, type: type, messageId: UUID().uuidString.lowercased())
            }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)) }
            await group.next()
            group.cancelAll()
        }
    }
}
