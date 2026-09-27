import Foundation
import KryptaCore

/// Anhänge: Fotos, Videos, Sprachnachrichten, Dateien.
///
/// Ablauf beim Senden: Datei mit eigenem Schlüssel verschlüsseln
/// (AttachmentCrypto), den Blob unter einer zufälligen Kennung hochladen,
/// dann die Nachricht mit `_att` schicken: Kennung, Schlüssel, SHA-256 des
/// Blobs, Größe, Art, MIME-Typ, ggf. Name, Maße, Dauer und ein kleines
/// Vorschaubild. Das alles steht in der Ende-zu-Ende-Verschlüsselung.
///
/// Beim Empfang holt die Engine den Blob sofort (ohne Anmeldung, siehe
/// BlobStore), prüft den Hash, entschlüsselt und legt den Inhalt in den
/// Tresor. Dann meldet sie `fetched`; haben alle Empfänger den Blob, löscht
/// ihn der Absender vom Server. Was niemand holt, räumt der Server nach
/// 48 Stunden weg.
///
/// Anhänge gelten wie Nachrichten: Löschfristen, „einmal ansehen", für
/// alle löschen. Verschwindet die Nachricht, verschwindet auch der Inhalt
/// aus dem Tresor. Mit Passwort geschützte Anhänge gibt es nicht.
public enum AttachmentPolicy {
    public static let maxThumbnail = 12 * 1024
    public static let maxNameLength = 200
    /// So lange merkt sich der Absender offene Blobs (der Server hält sie 48 h).
    static let pendingLifetime: TimeInterval = 49 * 3600
    static let maxDownloadAttempts = 3
}

extension MessengerEngine {
    public var supportsAttachments: Bool { blobs != nil }

    // MARK: - Senden

    /// Einen Anhang schicken. `caption` ist der Text dazu (darf leer sein).
    public func sendAttachment(chatId: String, _ out: OutgoingAttachment, caption: String = "", options: SendOptions = .plain) async {
        guard let blobs, !deletingChats.contains(chatId), canWrite(chatId: chatId), let chat = chat(chatId) else { return }
        guard let sealed = try? AttachmentCrypto.seal(out.data) else { return }
        let blobId = Self.newBlobId()
        let messageId = UUID().uuidString.lowercased()
        let oneTime = options.oneTime
        var attachment = Attachment(
            id: blobId, key: sealed.key, digest: sealed.digest, size: out.data.count, kind: out.kind,
            mime: String(out.mime.prefix(100)), name: out.name.map { String($0.prefix(AttachmentPolicy.maxNameLength)) },
            width: out.width, height: out.height, duration: out.duration,
            thumbnail: out.thumbnail.flatMap { $0.count <= AttachmentPolicy.maxThumbnail ? $0 : nil },
            state: .transferring
        )
        let replyTo = validReplyTarget(options.replyTo, in: chatId)

        var m = Message(id: messageId, chatId: chatId, senderId: userId, recipientId: chat.recipientId,
                        text: oneTime ? nil : caption, timestamp: Date(), status: .sending)
        m.selfDestruct = options.selfDestruct
        m.selfDestructFromChat = options.fromChatRule
        m.burnAfterRead = options.burnAfterRead && !oneTime
        m.oneTime = oneTime
        m.replyTo = replyTo
        // Einmal ansehen: der Absender behält nichts, nur den Hinweis.
        m.attachment = oneTime ? nil : attachment
        append(m, to: chatId)
        if !oneTime { storeAttachment(blobId, data: out.data) }

        func fail() {
            updateMessage(chatId, messageId) {
                $0.status = .failed
                if $0.attachment != nil { $0.attachment?.state = .failed }
            }
        }

        do {
            try await blobs.upload(sealed.blob, id: blobId)
        } catch {
            return fail()
        }

        attachment.state = .ready
        var extra = messageFields(options, replyTo: replyTo)
        extra["_att"] = attachmentField(attachment)

        let recipients: Set<String>
        if let g = chat.group {
            extra["_g"] = .string(g.id)
            let fields = extra
            recipients = await fanOut(chatId: chatId, members: g.members.filter { $0 != userId }, messageId: messageId, quiet: false, rememberCopies: true) { _ in
                (caption, fields)
            }
        } else {
            var reached: Set<String> = []
            let fields = extra
            await enqueue(chatId) { [self] in
                guard let contact = contact(chat.recipientId), sendBlockReason(contact) == nil else { return }
                if let delivery = try? await transmit(chatId: chatId, contact: contact, messageId: messageId, content: caption, extra: fields) {
                    rememberServerCopy(messageId: messageId, to: contact.id, delivery: delivery)
                    reached.insert(contact.id)
                }
            }
            recipients = reached
        }
        guard !recipients.isEmpty else {
            try? await blobs.delete(id: blobId)
            return fail()
        }
        rememberPendingBlob(blobId, messageId: messageId, waiting: Array(recipients))
        updateMessage(chatId, messageId) {
            if $0.status == .sending { $0.status = .sent }
            if $0.attachment != nil { $0.attachment?.state = .ready }
        }
    }

    /// Die Felder aus den Sendeoptionen, wie im Einzel- und Gruppenchat.
    func messageFields(_ options: SendOptions, replyTo: String?) -> JSONObject {
        var extra: JSONObject = [:]
        if let sd = options.selfDestruct { extra["_sd"] = .int(Int(sd * 1000)) }
        if options.fromChatRule { extra["_sdc"] = true }
        if options.burnAfterRead && !options.oneTime { extra["_bar"] = true }
        if options.oneTime { extra["_once"] = true }
        if let replyTo { extra["_re"] = .string(replyTo) }
        return extra
    }

    static func newBlobId() -> String {
        Data.random(count: 16).map { String(format: "%02x", $0) }.joined()
    }

    func attachmentField(_ a: Attachment) -> JSONValue {
        var map: JSONObject = [
            "id": .string(a.id), "k": .string(a.key.base64), "d": .string(a.digest.base64),
            "s": .int(a.size), "c": .string(a.kind.rawValue), "m": .string(a.mime),
        ]
        if let n = a.name { map["n"] = .string(n) }
        if let w = a.width { map["w"] = .int(w) }
        if let h = a.height { map["hi"] = .int(h) }
        if let t = a.duration { map["t"] = .double(t) }
        if let th = a.thumbnail { map["th"] = .string(th.base64) }
        return .object(map)
    }

    /// `_att` streng lesen: alles, was nicht passt, heißt „kein Anhang".
    static func parseAttachment(_ value: JSONValue?) -> Attachment? {
        guard let o = value?.objectValue,
              let id = o["id"]?.stringValue, GroupPolicy.isValidId(id),
              let key = o["k"]?.stringValue.flatMap({ Data(base64: $0) }), key.count == 32,
              let digest = o["d"]?.stringValue.flatMap({ Data(base64: $0) }), digest.count == 32,
              let size = o["s"]?.intValue, (1...AttachmentCrypto.maxSize).contains(size),
              let kind = o["c"]?.stringValue.flatMap(AttachmentKind.init(rawValue:)),
              let mime = o["m"]?.stringValue, (1...100).contains(mime.count) else { return nil }
        var a = Attachment(id: id, key: key, digest: digest, size: size, kind: kind, mime: mime, state: .transferring)
        if let n = o["n"]?.stringValue, !n.isEmpty { a.name = String(n.prefix(AttachmentPolicy.maxNameLength)) }
        if let w = o["w"]?.intValue, (1...20_000).contains(w) { a.width = w }
        if let h = o["hi"]?.intValue, (1...20_000).contains(h) { a.height = h }
        let t: Double? = {
            switch o["t"] {
            case .double(let d)?: return d
            case .int(let i)?: return Double(i)
            default: return nil
            }
        }()
        if let t, t >= 0, t <= 24 * 3600 { a.duration = t }
        if let th = o["th"]?.stringValue.flatMap({ Data(base64: $0) }), th.count <= AttachmentPolicy.maxThumbnail { a.thumbnail = th }
        return a
    }

    func rememberPendingBlob(_ id: String, messageId: String, waiting: [String]) {
        var list = meta.pendingBlobs ?? []
        let cutoff = Date().addingTimeInterval(-AttachmentPolicy.pendingLifetime)
        list.removeAll { $0.at < cutoff }
        list.append(.init(id: id, messageId: messageId, waiting: waiting, at: Date()))
        meta.pendingBlobs = list
        saveMeta()
    }

    // MARK: - Empfangen

    /// Den Blob holen, prüfen, entschlüsseln, in den Tresor legen. Läuft im
    /// Hintergrund; der Posteingang wartet nicht darauf.
    func fetchAttachment(chatId: String, messageId: String) {
        guard let blobs, downloadsInFlight.insert(messageId).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { self.downloadsInFlight.remove(messageId) }
            guard let a = self.messages(in: chatId).first(where: { $0.id == messageId })?.attachment else { return }
            var data: Data?
            for attempt in 0..<AttachmentPolicy.maxDownloadAttempts {
                if let blob = try? await blobs.download(id: a.id, maxSize: AttachmentCrypto.maxBlobSize),
                   let plain = try? AttachmentCrypto.open(blob, key: a.key, digest: a.digest), plain.count == a.size {
                    data = plain
                    break
                }
                try? await Task.sleep(for: .seconds(Double(1 << attempt)))
            }
            // In der Zwischenzeit gelöscht oder abgelaufen: nichts ablegen.
            guard let m = self.messages(in: chatId).first(where: { $0.id == messageId }), m.attachment != nil else { return }
            guard let data else {
                self.updateMessage(chatId, messageId) { $0.attachment?.state = .failed }
                return
            }
            self.storeAttachment(a.id, data: data)
            self.updateMessage(chatId, messageId) { $0.attachment?.state = .ready }
            // Dem Absender sagen, dass er den Blob löschen kann.
            if let sender = self.contact(m.senderId) {
                self.sendControlLater(chatId: chatId, contact: sender, type: "fetched", messageId: messageId)
            }
        }
    }

    /// Erneut holen (nach einem Fehler).
    public func retryAttachment(chatId: String, messageId: String) {
        guard let m = messages(in: chatId).first(where: { $0.id == messageId }), m.senderId != userId,
              let a = m.attachment, a.state == .failed else { return }
        updateMessage(chatId, messageId) { $0.attachment?.state = .transferring }
        fetchAttachment(chatId: chatId, messageId: messageId)
    }

    /// Beim Start: was noch nicht geholt ist, holen.
    func resumeAttachments() {
        for (chatId, list) in messages {
            for m in list where m.senderId != userId && m.attachment?.state == .transferring {
                fetchAttachment(chatId: chatId, messageId: m.id)
            }
        }
        let cutoff = Date().addingTimeInterval(-AttachmentPolicy.pendingLifetime)
        if let list = meta.pendingBlobs, list.contains(where: { $0.at < cutoff }) {
            meta.pendingBlobs = list.filter { $0.at >= cutoff }
            saveMeta()
        }
    }

    /// Ein Empfänger hat den Blob: haben ihn alle, weg damit vom Server.
    /// Wer gar nicht auf der Liste steht, ändert nichts.
    func applyFetched(messageId: String, from peer: String) {
        guard var list = meta.pendingBlobs, let i = list.firstIndex(where: { $0.messageId == messageId }),
              list[i].waiting.contains(peer) else { return }
        list[i].waiting.removeAll { $0 == peer }
        let blobId = list[i].id
        let done = list[i].waiting.isEmpty
        if done { list.remove(at: i) }
        meta.pendingBlobs = list.isEmpty ? nil : list
        saveMeta()
        if done, let blobs { Task { try? await blobs.delete(id: blobId) } }
    }

    // MARK: - Lesen

    /// Der Inhalt eines Anhangs aus dem Tresor.
    public func attachmentData(_ m: Message) -> Data? {
        guard let a = m.attachment, a.state == .ready else { return nil }
        return try? vault.load(a.slot)
    }

    /// Einmal ansehen: der Inhalt kommt genau einmal heraus, dann ist die
    /// Nachricht weg (wie consumeOneTime für Text).
    public func openOneTimeAttachment(chatId: String, messageId: String) -> (Data, Attachment)? {
        guard let m = messages[chatId]?.first(where: { $0.id == messageId }), m.oneTime, m.senderId != userId,
              let a = m.attachment, a.state == .ready, let data = try? vault.load(a.slot) else { return nil }
        messages[chatId]?.removeAll { $0.id == messageId }
        saveMessages(chatId)
        reportBurn(chatId: chatId, messageId: messageId, to: m.senderId)
        return (data, a)
    }

    // MARK: - Tresor

    func storeAttachment(_ id: String, data: Data) {
        try? vault.save(data, slot: "att.\(id)")
        var slots = meta.attachmentSlots ?? []
        if !slots.contains(id) {
            slots.append(id)
            meta.attachmentSlots = slots
            saveMeta()
        }
    }

    /// Nach dem Speichern von Nachrichten: Inhalte, zu denen es keine
    /// Nachricht mehr gibt, aus dem Tresor löschen. Einmal je Durchlauf.
    func scheduleAttachmentSweep() {
        guard !(meta.attachmentSlots ?? []).isEmpty, !sweepScheduled else { return }
        sweepScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.sweepScheduled = false
            self.sweepAttachments()
        }
    }

    func sweepAttachments() {
        guard let slots = meta.attachmentSlots, !slots.isEmpty else { return }
        var referenced: Set<String> = []
        for list in messages.values {
            for m in list { if let id = m.attachment?.id { referenced.insert(id) } }
        }
        let orphans = slots.filter { !referenced.contains($0) }
        guard !orphans.isEmpty else { return }
        for id in orphans { try? vault.delete("att.\(id)") }
        let kept = slots.filter { referenced.contains($0) }
        meta.attachmentSlots = kept.isEmpty ? nil : kept
        saveMeta()
    }
}
