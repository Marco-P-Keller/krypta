import Foundation
import KryptaCore

/// Gruppen ohne Gruppenserver: jede Gruppennachricht geht einzeln über die
/// bestehende Sitzung mit jedem Mitglied (Fan-out), mit derselben Kennung.
/// Double Ratchet, Sealed Sender und Wiedereinspiel-Schutz gelten also
/// unverändert; der Server sieht nur einzelne Nachrichten und erfährt nicht,
/// dass es eine Gruppe gibt.
///
/// In der Verschlüsselung:
/// - `_g`: Kennung der Gruppe an jeder Gruppennachricht (auch an Reaktionen,
///   Bearbeitungen und `_ev`-Hinweisen).
/// - `_grp`: der Stand der Gruppe `{id, n, v, a, m: [{u, k}], s, t?, r?}`.
///   Nur die Verwalterin (`a`) ändert ihn; es gilt die höhere Version `v`.
/// - `_gl`: Austritt. Tritt die Verwalterin aus, übernimmt das Mitglied mit
///   der kleinsten Kennung; das rechnet jedes Gerät gleich.
///
/// Mitglieder, die man selbst nicht kennt, stellt die Verwalterin vor: mit
/// Kennung und Identitätsschlüssel. Übernommen wird ein solcher Kontakt nur,
/// wenn der Server denselben Schlüssel nennt, und er bleibt unbestätigt, bis
/// man die Sicherheitsnummer vergleicht. Namen reisen nicht mit: wie jemand
/// in meinem Adressbuch heißt, geht die anderen nichts an.
///
/// Zahlungen gibt es nur im Einzelchat.
public enum GroupPolicy {
    public static let maxMembers = 32
    public static let maxNameLength = 64

    static func isValidId(_ id: String) -> Bool {
        id.count == 32 && id.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
    }

    /// Wer übernimmt, wenn die Verwalterin geht.
    static func successor(of members: [String]) -> String? {
        members.min { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    static func cleanName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return String(name.prefix(maxNameLength))
    }
}

extension MessengerEngine {
    // MARK: - Lesen

    public func group(_ chatId: String) -> GroupInfo? { chat(chatId)?.group }

    func groupChat(id groupId: String) -> Chat? { chats.first { $0.group?.id == groupId } }

    /// Name eines Mitglieds, wie ich es kenne: mein Name für den Kontakt,
    /// sonst der Platzhalter aus der Kennung.
    public func memberName(_ uid: String) -> String {
        if let chat = chat(forContact: uid) { return chat.name }
        return contact(uid)?.displayName ?? Contact.defaultName(for: uid)
    }

    /// Wen man in eine Gruppe holen kann: angenommene Kontakte mit der
    /// nativen App, nicht gesperrt, Schlüssel unverändert.
    public var groupCandidates: [Contact] {
        contacts.filter { sendBlockReason($0) == nil && Self.understandsExtras($0) }
            .sorted { memberName($0.id).localizedCaseInsensitiveCompare(memberName($1.id)) == .orderedAscending }
    }

    /// Kann ich in diesem Chat schreiben?
    public func canWrite(chatId: String) -> Bool {
        guard let chat = chat(chatId) else { return false }
        if let group = chat.group { return !group.hasLeft }
        return contact(chat.recipientId)?.canSendMessages == true
    }

    // MARK: - Anlegen und verwalten

    /// Neue Gruppe mit mir als Verwalterin. Gibt die Chat-Kennung zurück.
    public func createGroup(name rawName: String, memberIds: [String]) async -> String? {
        guard let name = GroupPolicy.cleanName(rawName) else { return nil }
        let candidates = Set(groupCandidates.map(\.id))
        let others = Array(Set(memberIds)).filter { $0 != userId && candidates.contains($0) }
        guard !others.isEmpty, others.count < GroupPolicy.maxMembers else { return nil }

        let gid = Data.random(count: 16).map { String(format: "%02x", $0) }.joined()
        var keys: [String: Data] = [userId: identity.publicKey]
        for id in others { keys[id] = contact(id)?.publicKey }
        var info = GroupInfo(id: gid, name: name, members: [userId] + others.sorted(), admin: userId, version: 1,
                             secret: Data.random(count: 32), keys: keys)
        info.unsynced = others
        var chat = Chat(recipientId: "group:\(gid)", name: name)
        chat.group = info
        chat.lastActivity = Date()
        switch defaultChatRule {
        case .off: break
        case .timer(let t): chat.timer = t; chat.timerSetAt = Date()
        case .afterRead: chat.deleteAfterRead = true
        }
        chats.append(chat)
        messages[chat.id] = []
        saveChats()
        appendSystemEvent(chatId: chat.id, kind: .groupCreated, senderId: userId, messageId: UUID().uuidString.lowercased(), text: name)
        await syncGroup(chat.id)
        return chat.id
    }

    public func renameGroup(_ chatId: String, to rawName: String) async {
        guard let name = GroupPolicy.cleanName(rawName), var g = adminGroup(chatId), g.name != name else { return }
        g.name = name
        commitAdminChange(chatId, g, event: (.groupRenamed, name))
        updateChat(chatId) { $0.name = name }
        await syncGroup(chatId)
    }

    public func addMembers(_ chatId: String, _ ids: [String]) async {
        guard var g = adminGroup(chatId) else { return }
        let candidates = Set(groupCandidates.map(\.id))
        let fresh = ids.filter { !g.members.contains($0) && candidates.contains($0) }
        guard !fresh.isEmpty, g.members.count + fresh.count <= GroupPolicy.maxMembers else { return }
        g.members += fresh
        for id in fresh { g.keys[id] = contact(id)?.publicKey }
        commitAdminChange(chatId, g, event: nil)
        for id in fresh {
            appendSystemEvent(chatId: chatId, kind: .groupMemberAdded, senderId: userId, messageId: UUID().uuidString.lowercased(), text: id)
        }
        await syncGroup(chatId)
    }

    /// Ein Mitglied entfernen. Es bekommt den neuen Stand auch, damit seine
    /// App weiß, dass es nicht mehr dabei ist.
    public func removeMember(_ chatId: String, _ id: String) async {
        guard var g = adminGroup(chatId), id != userId, g.members.contains(id) else { return }
        g.members.removeAll { $0 == id }
        g.keys.removeValue(forKey: id)
        commitAdminChange(chatId, g, event: (.groupMemberRemoved, id))
        await syncGroup(chatId, extra: [id])
    }

    /// Löschfrist der Gruppe (nur die Verwalterin).
    public func setGroupRule(_ chatId: String, timer: TimeInterval?, afterRead: Bool) async {
        guard let g = adminGroup(chatId) else { return }
        let t = afterRead ? nil : timer
        updateChat(chatId) {
            $0.timer = t
            $0.timerSetAt = t == nil ? nil : Date()
            $0.deleteAfterRead = afterRead
        }
        commitAdminChange(chatId, g, event: nil)
        appendSystemEvent(chatId: chatId, kind: afterRead ? .selfDestructAfterRead : .selfDestructChanged, senderId: userId,
                          messageId: UUID().uuidString.lowercased(), timer: t)
        await syncGroup(chatId)
    }

    /// Austreten: alle erfahren es, der Chat bleibt zum Lesen.
    public func leaveGroup(_ chatId: String) async {
        guard let chat = chat(chatId), var g = chat.group, !g.hasLeft else { return }
        let others = g.members.filter { $0 != userId }
        let gid = g.id
        await fanOut(chatId: chatId, members: others, messageId: UUID().uuidString.lowercased(), quiet: true) { _ in
            ("", ["_gl": .string(gid)])
        }
        g.left = true
        g.unsynced = nil
        g.members.removeAll { $0 == userId }
        updateChat(chatId) { $0.group = g }
        remember(leftGroup: g.id)
        appendSystemEvent(chatId: chatId, kind: .groupLeft, senderId: userId, messageId: UUID().uuidString.lowercased())
    }

    /// Die Gruppe, wenn ich sie verwalte und noch dabei bin.
    func adminGroup(_ chatId: String) -> GroupInfo? {
        guard let g = group(chatId), !g.hasLeft, g.isAdmin(userId) else { return nil }
        return g
    }

    /// Neuer Stand: Version hoch, alle anderen Mitglieder müssen ihn bekommen.
    func commitAdminChange(_ chatId: String, _ changed: GroupInfo, event: (SystemEventKind, String)?) {
        var g = changed
        g.version += 1
        g.unsynced = g.members.filter { $0 != userId }
        updateChat(chatId) { $0.group = g }
        if let event {
            appendSystemEvent(chatId: chatId, kind: event.0, senderId: userId, messageId: UUID().uuidString.lowercased(), text: event.1)
        }
    }

    func remember(leftGroup id: String) {
        var list = meta.leftGroups ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        if list.count > 200 { list.removeFirst(list.count - 200) }
        meta.leftGroups = list
        saveMeta()
    }

    /// Den aktuellen Stand an alle, die ihn noch nicht haben (und an `extra`).
    func syncGroup(_ chatId: String, extra: [String] = []) async {
        guard let chat = chat(chatId), let g = chat.group, g.isAdmin(userId), !g.hasLeft else { return }
        let targets = Array(Set((g.unsynced ?? []) + extra)).filter { $0 != userId }
        guard !targets.isEmpty else { return }
        let payload = groupPayload(g, chat: chat)
        let reached = await fanOut(chatId: chatId, members: targets, messageId: UUID().uuidString.lowercased(), quiet: false, pairTags: true) { _ in
            ("", ["_grp": payload])
        }
        updateChat(chatId) { c in
            guard var current = c.group, current.version == g.version else { return }
            let left = (current.unsynced ?? []).filter { !reached.contains($0) }
            current.unsynced = left.isEmpty ? nil : left
            c.group = current
        }
    }

    /// Beim Start: was als Verwalterin noch nicht bei allen ankam, erneut.
    func resyncGroups() {
        let ids = chats.filter { $0.group.map { $0.isAdmin(userId) && !$0.hasLeft && !($0.unsynced ?? []).isEmpty } ?? false }.map(\.id)
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            for id in ids { await self?.syncGroup(id) }
        }
    }

    func groupPayload(_ g: GroupInfo, chat: Chat) -> JSONValue {
        var map: JSONObject = [
            "id": .string(g.id), "n": .string(g.name), "v": .int(g.version), "a": .string(g.admin),
            "s": .string(g.secret.base64),
            "m": .array(g.members.map { uid in
                .object(["u": .string(uid), "k": .string((uid == userId ? identity.publicKey : g.keys[uid] ?? contact(uid)?.publicKey ?? Data()).base64)])
            }),
        ]
        if chat.deleteAfterRead { map["r"] = true } else if let t = chat.timer { map["t"] = .int(Int(t * 1000)) }
        return .object(map)
    }

    // MARK: - Senden

    /// Eine Gruppennachricht: ein Eintrag im Verlauf, eine verschlüsselte
    /// Nachricht je Mitglied, alle mit derselben Kennung.
    func sendGroup(chatId: String, text: String, options: SendOptions) async {
        guard !deletingChats.contains(chatId), let chat = chat(chatId), let g = chat.group, !g.hasLeft else { return }
        let messageId = UUID().uuidString.lowercased()
        let password = options.password.flatMap { $0.isEmpty ? nil : $0 }
        let oneTime = options.oneTime
        let replyTo = validReplyTarget(options.replyTo, in: chatId)

        var m = Message(id: messageId, chatId: chatId, senderId: userId, recipientId: chat.recipientId,
                        text: oneTime ? nil : text, timestamp: Date(), status: .sending)
        m.selfDestruct = options.selfDestruct
        m.selfDestructFromChat = options.fromChatRule
        m.burnAfterRead = options.burnAfterRead && !oneTime
        m.oneTime = oneTime
        m.isPasswordProtected = password != nil
        m.passwordUnlocked = password == nil
        m.replyTo = replyTo
        append(m, to: chatId)

        var extra: JSONObject = ["_g": .string(g.id)]
        if let sd = options.selfDestruct { extra["_sd"] = .int(Int(sd * 1000)) }
        if options.fromChatRule { extra["_sdc"] = true }
        if options.burnAfterRead && !oneTime { extra["_bar"] = true }
        if oneTime { extra["_once"] = true }
        if password != nil { extra["_pw"] = true }
        if let replyTo { extra["_re"] = .string(replyTo) }

        let others = g.members.filter { $0 != userId }
        let reached = await fanOut(chatId: chatId, members: others, messageId: messageId, quiet: false, rememberCopies: true) { [self] member in
            guard let password else { return (text, extra) }
            // Je Mitglied gebunden, wie im Einzelchat (H4-Crypto).
            guard let blob = try? Envelope.encryptWithPassword(text, password: password, aad: "pwd-v1|\(userId)|\(member.id)|\(messageId)") else { return nil }
            return (blob, extra)
        }
        // Allein in der Gruppe: die Nachricht bleibt, aber niemand bekommt sie.
        let ok = !reached.isEmpty || others.isEmpty
        updateMessage(chatId, messageId) { if $0.status == .sending { $0.status = ok ? .sent : .failed } }
    }

    /// Eine Nachricht ohne Verlaufseintrag an die Gruppe (Reaktion,
    /// Bearbeitung, Hinweis).
    func sendGroupSide(chatId: String, fields: JSONObject, content: String = "") async {
        guard let g = group(chatId), !g.hasLeft else { return }
        var extra = fields
        extra["_g"] = .string(g.id)
        await fanOut(chatId: chatId, members: g.members.filter { $0 != userId }, messageId: UUID().uuidString.lowercased(), quiet: true) { _ in
            (content, extra)
        }
    }

    /// An jedes Mitglied über die Sitzung mit ihm, gleichzeitig. Gibt zurück,
    /// wer die Nachricht bekommen hat. `build` liefert je Mitglied Inhalt und
    /// Felder (`nil`: an dieses nicht).
    @discardableResult
    func fanOut(chatId: String, members: [String], messageId: String, quiet: Bool, pairTags: Bool = false, rememberCopies: Bool = false,
                build: @escaping @MainActor @Sendable (Contact) -> (String, JSONObject)?) async -> Set<String> {
        let tag = quiet || pairTags ? nil : group(chatId).map(groupTag)
        var reached: Set<String> = []
        await withTaskGroup(of: String?.self) { tasks in
            for uid in members {
                tasks.addTask { @MainActor [self] in
                    guard let c = contact(uid), sendBlockReason(c) == nil, let built = build(c) else { return nil }
                    let (content, extra) = built
                    let pair = pairChat(for: c)
                    var ok = false
                    await enqueue(pair) { [self] in
                        guard let current = contact(uid), sendBlockReason(current) == nil else { return }
                        do {
                            let delivery = try await transmit(chatId: pair, contact: current, messageId: messageId, content: content, extra: extra,
                                                              quiet: quiet, tagOverride: tag)
                            if rememberCopies { rememberServerCopy(messageId: Self.copyKey(messageId, uid), to: uid, delivery: delivery) }
                            ok = true
                        } catch {}
                    }
                    return ok ? uid : nil
                }
            }
            for await uid in tasks { if let uid { reached.insert(uid) } }
        }
        return reached
    }

    static func copyKey(_ messageId: String, _ to: String) -> String { "\(messageId)|\(to)" }

    /// Der Einzelchat, in dem die Sitzung mit diesem Kontakt liegt; fehlt er
    /// (Mitglied aus einer Gruppe), entsteht er unsichtbar.
    @discardableResult
    func pairChat(for contact: Contact) -> String {
        if let existing = chat(forContact: contact.id) { return existing.id }
        var chat = Chat(recipientId: contact.id, name: contact.displayName)
        chat.hidden = true
        chats.append(chat)
        messages[chat.id] = []
        saveChats()
        return chat.id
    }

    /// Anhänger für Gruppennachrichten: aus dem Zufall der Gruppe, damit die
    /// Mitteilung den Gruppennamen zeigen kann.
    func groupTag(_ g: GroupInfo) -> String {
        NotificationTag.make(key: Self.groupTagKey(g))
    }

    static func groupTagKey(_ g: GroupInfo) -> Data {
        Primitives.hkdfSHA256(ikm: g.secret, salt: Data(count: 32), info: "KryptaNotifyGroup-v1|\(g.id)".utf8Data, length: 32)
    }

    // MARK: - Empfangen

    /// Stand einer Gruppe von einem Kontakt übernehmen: neue Gruppe (ich bin
    /// eingeladen) oder Änderung durch die Verwalterin.
    func applyGroupUpdate(from sender: Contact, map: JSONObject) async {
        guard let parsed = parseGroup(map) else { return }
        let incoming = parsed.info
        guard incoming.members.contains(sender.id), incoming.admin == sender.id else { return }

        if let chat = groupChat(id: incoming.id), let current = chat.group {
            // Nur die aktuelle Verwalterin, nur vorwärts.
            guard current.admin == sender.id, incoming.version > current.version, !current.hasLeft else { return }
            let before = Set(current.members)
            let after = Set(incoming.members)
            if !after.contains(userId) {
                var gone = current
                gone.left = true
                gone.version = incoming.version
                gone.members = incoming.members
                updateChat(chat.id) { $0.group = gone }
                remember(leftGroup: incoming.id)
                appendSystemEvent(chatId: chat.id, kind: .groupRemovedYou, senderId: sender.id, messageId: UUID().uuidString.lowercased())
                return
            }
            await introduce(incoming, by: sender.id)
            updateChat(chat.id) { c in
                c.group = incoming
                c.name = incoming.name
                if c.timer != parsed.timer || c.deleteAfterRead != parsed.afterRead {
                    c.timer = parsed.timer
                    c.timerSetAt = parsed.timer == nil ? nil : Date()
                    c.deleteAfterRead = parsed.afterRead
                }
            }
            if current.name != incoming.name {
                appendSystemEvent(chatId: chat.id, kind: .groupRenamed, senderId: sender.id, messageId: UUID().uuidString.lowercased(), text: incoming.name)
            }
            for uid in after.subtracting(before).sorted() {
                appendSystemEvent(chatId: chat.id, kind: .groupMemberAdded, senderId: sender.id, messageId: UUID().uuidString.lowercased(), text: uid)
            }
            for uid in before.subtracting(after).sorted() where uid != sender.id {
                appendSystemEvent(chatId: chat.id, kind: .groupMemberRemoved, senderId: sender.id, messageId: UUID().uuidString.lowercased(), text: uid)
            }
            if (chat.timer != parsed.timer || chat.deleteAfterRead != parsed.afterRead) {
                appendSystemEvent(chatId: chat.id, kind: parsed.afterRead ? .selfDestructAfterRead : .selfDestructChanged, senderId: sender.id,
                                  messageId: UUID().uuidString.lowercased(), timer: parsed.timer)
            }
            return
        }

        // Neue Gruppe: nur von einem angenommenen Kontakt, und nicht, wenn ich
        // aus genau dieser Gruppe ausgetreten bin.
        guard incoming.members.contains(userId), sender.requestState == .established, !sender.isBlocked,
              !(meta.leftGroups ?? []).contains(incoming.id) else { return }
        await introduce(incoming, by: sender.id)
        var chat = Chat(recipientId: "group:\(incoming.id)", name: incoming.name)
        chat.group = incoming
        chat.lastActivity = Date()
        chat.timer = parsed.timer
        chat.timerSetAt = parsed.timer == nil ? nil : Date()
        chat.deleteAfterRead = parsed.afterRead
        chats.append(chat)
        messages[chat.id] = []
        saveChats()
        appendSystemEvent(chatId: chat.id, kind: .groupJoined, senderId: sender.id, messageId: UUID().uuidString.lowercased(), text: incoming.name)
    }

    struct ParsedGroup {
        var info: GroupInfo
        var timer: TimeInterval?
        var afterRead: Bool
    }

    func parseGroup(_ map: JSONObject) -> ParsedGroup? {
        guard let id = map["id"]?.stringValue, GroupPolicy.isValidId(id),
              let rawName = map["n"]?.stringValue, let name = GroupPolicy.cleanName(rawName),
              let version = map["v"]?.intValue, version >= 1,
              let admin = map["a"]?.stringValue, QRPayload.isValidUserId(admin),
              let secretB64 = map["s"]?.stringValue, let secret = Data(base64: secretB64), secret.count == 32,
              let list = map["m"]?.arrayValue, (2...GroupPolicy.maxMembers).contains(list.count) else { return nil }
        var members: [String] = []
        var keys: [String: Data] = [:]
        for entry in list {
            guard let o = entry.objectValue, let uid = o["u"]?.stringValue, QRPayload.isValidUserId(uid), !members.contains(uid),
                  let k = o["k"]?.stringValue, let key = Data(base64: k), key.count == 32 else { return nil }
            members.append(uid)
            keys[uid] = key
        }
        let info = GroupInfo(id: id, name: name, members: members, admin: admin, version: version, secret: secret, keys: keys)
        let afterRead = map["r"] == true
        let timer = afterRead ? nil : map["t"]?.intValue.flatMap(SelfDestructPolicy.clamp(ms:))
        return ParsedGroup(info: info, timer: timer, afterRead: afterRead)
    }

    /// Unbekannte Mitglieder als Kontakte anlegen — nur, wenn der Server
    /// denselben Schlüssel nennt wie die Verwalterin.
    func introduce(_ g: GroupInfo, by introducer: String) async {
        for uid in g.members where uid != userId && contact(uid) == nil {
            guard let announced = g.keys[uid],
                  let serverB64 = try? await relay.publicKey(uid: uid), let serverKey = Data(base64: serverB64),
                  serverKey.constantTimeEquals(announced), contact(uid) == nil else { continue }
            var c = Contact(id: uid, publicKey: announced, requestState: .established)
            c.introducedBy = introducer
            contacts.append(c)
            saveContacts()
            pairChat(for: c)
            Task { [weak self] in await self?.verifyTransparency(uid) }
        }
    }

    /// Ein Mitglied tritt aus. Ging die Verwalterin, übernimmt die kleinste
    /// Kennung; bin ich das, geht der neue Stand an alle.
    func applyGroupLeave(from senderId: String, groupId: String) async {
        guard let chat = groupChat(id: groupId), var g = chat.group, !g.hasLeft, g.members.contains(senderId) else { return }
        g.members.removeAll { $0 == senderId }
        g.keys.removeValue(forKey: senderId)
        g.unsynced = g.unsynced?.filter { $0 != senderId }
        let adminLeft = g.admin == senderId
        if adminLeft, let next = GroupPolicy.successor(of: g.members) { g.admin = next }
        updateChat(chat.id) { $0.group = g }
        appendSystemEvent(chatId: chat.id, kind: .groupMemberLeft, senderId: senderId, messageId: UUID().uuidString.lowercased(), text: senderId)
        if g.isAdmin(userId) {
            commitAdminChange(chat.id, g, event: nil)
            await syncGroup(chat.id)
        }
    }

    /// Wohin eine Nachricht gehört: ohne `_g` in den Einzelchat, mit `_g` in
    /// die Gruppe — wenn es sie gibt, ich dabei bin und der Absender auch.
    /// `nil`: verwerfen.
    func targetChat(for inner: JSONObject, pairChatId: String, senderId: String) -> String? {
        guard let gid = inner["_g"]?.stringValue else { return pairChatId }
        guard let chat = groupChat(id: gid), let g = chat.group, !g.hasLeft, g.members.contains(senderId) else { return nil }
        return chat.id
    }

    /// Einträge für die Mitteilungen: je Gruppe Schlüssel und Name.
    func groupNotificationEntries() -> [NotificationIndex.Entry] {
        chats.compactMap { chat in
            guard let g = chat.group, !g.hasLeft else { return nil }
            // `group:<Kennung>` wie `recipientId`: chat(forContact:) findet ihn.
            return .init(key: Self.groupTagKey(g), name: chat.name, contactId: chat.recipientId, mutedUntil: chat.mutedUntil)
        }
    }
}
