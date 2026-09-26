import Foundation
import KryptaCore

/// Übernimmt, was die Flutter-App gespeichert hat.
///
/// Die native App ersetzt die Flutter-App im App Store unter derselben
/// Bundle-ID; nach dem Update liegen deren Daten noch im Container und im
/// Schlüsselbund. Hier werden sie in das Format der Engine übersetzt — ohne
/// Plattform: Schlüsselbund, Dateien und Secure Enclave liest die App
/// (FlutterMigration.swift) und reicht die entschlüsselten Texte herein.
///
/// Die Formate stehen in lib/features/messenger/data/models/*.dart
/// (`toMap`), lib/services/storage/encrypted_local_store.dart und
/// lib/core/constants/storage_keys.dart.
public enum FlutterImport {
    /// Was aus `krypta_store/*.enc` kam: Slotname (= Dateiname ohne `.enc`)
    /// → JSON-Text.
    public typealias Store = [String: String]
    /// Was flutter_secure_storage im Schlüsselbund hat: Schlüssel → Wert.
    public typealias Secrets = [String: String]

    public struct Settings: Equatable, Sendable {
        public var secretCodeHash: String?
        public var deleteCodeHash: String?
        public var calculatorLock: Bool
        public var biometricLock: Bool
        public var vaultPasswordHash: String?
        public var vaultFailures: Int
        public var vaultLastFailMs: Int?
        public var pushEnabled: Bool
        public var languageCode: String?
    }

    public struct Result: Sendable {
        public var userId: String
        public var identity: KeyPair
        public var settings: Settings
        public var contacts: [Contact]
        public var chats: [Chat]
        public var messages: [String: [Message]]
        /// Chat → Ratchet-Zustand als JSON-Text (dasselbe Format in beiden Welten).
        public var ratchets: [String: String]
        public var preKeys: PreKeyStore?
        public var counters: ControlCounter?
        public var transparency: [String: TransparencyChain]
        var meta: EngineMeta
    }

    public enum Failure: Error, Equatable {
        case noIdentity
        case noUserId
    }

    // MARK: - Übersetzen

    public static func convert(secrets: Secrets, store: Store) throws -> Result {
        guard let priv = secrets["krypta_id_priv"].flatMap(Data.init(base64:)),
              let identity = try? KeyPair.from(privateKey: priv) else { throw Failure.noIdentity }
        if let pub = secrets["krypta_id_pub"].flatMap(Data.init(base64:)), pub != identity.publicKey { throw Failure.noIdentity }
        guard let userId = secrets["krypta_cfg_userid"], !userId.isEmpty else { throw Failure.noUserId }

        let secret = secrets["krypta_code_secret"]
        let settings = Settings(
            secretCodeHash: secret,
            deleteCodeHash: secrets["krypta_code_delete"],
            // Fehlt der Schalter, gilt an — aber nur, wenn es einen Code gibt.
            calculatorLock: secret != nil && secrets["krypta_cfg_calculator_lock"] != "false",
            biometricLock: secrets["krypta_cfg_biometric"] == "true",
            vaultPasswordHash: secrets["krypta_vault_enabled"] == "true" ? secrets["krypta_vault_hash"] : nil,
            vaultFailures: Int(secrets["krypta_vault_fails"] ?? "") ?? 0,
            vaultLastFailMs: Int(secrets["krypta_vault_lastfail"] ?? ""),
            // Umgekehrt gespeichert: "true" hieß „keine Mitteilungen".
            pushEnabled: secrets["krypta_cfg_push_privacy"] != "true",
            languageCode: secrets["krypta_cfg_language"]
        )

        let contacts = list(store["contacts"]).compactMap(contact)
        let chats = list(store["chats"]).compactMap(chat)
        var messages: [String: [Message]] = [:]
        var ratchets: [String: String] = [:]
        for c in chats {
            messages[c.id] = list(store["msg_\(c.id)"]).compactMap(message)
            // Nur übernehmen, was die Engine auch lesen kann.
            if let text = store["ratchet_\(c.id)"], let map = try? JSONObject.parse(text), (try? RatchetState(json: map)) != nil {
                ratchets[c.id] = text
            }
        }

        var meta = EngineMeta()
        meta.readReceipts = secrets["krypta_cfg_read_receipts"] == "true"
        meta.chatPreview = secrets["krypta_cfg_chat_preview"] != "false"
        meta.processedIds = Array(strings(store["processed_ids"]).suffix(1000))
        if let eks = object(store["hs_accepted_eks"]) {
            meta.acceptedEks = eks.compactMapValues { $0.arrayValue?.compactMap(\.stringValue) }
        }
        if let lineage = object(store["peer_psid_lineage"]) {
            let byChat = Dictionary(chats.map { ($0.id, $0.recipientId) }, uniquingKeysWith: { a, _ in a })
            for (key, value) in lineage {
                // Bis 31.08. lag die Spur unter der Chat-Kennung.
                let person = byChat[key] ?? key
                let ids = value.arrayValue?.compactMap(\.stringValue) ?? []
                meta.psidLineage[person, default: []].append(contentsOf: ids.filter { !(meta.psidLineage[person] ?? []).contains($0) })
            }
        }
        if let attempts = object(store["unlock_attempts"]) {
            for (id, value) in attempts {
                guard let o = value.objectValue, let f = o["f"]?.intValue, let t = o["t"]?.intValue else { continue }
                meta.unlockAttempts[id] = .init(fails: f, last: Date(ms: t))
            }
        }
        meta.pendingBurns = list(store["ausstehende_meldungen"]).compactMap { o in
            guard o["art"]?.stringValue == "burned", let chatId = o["chatId"]?.stringValue,
                  let messageId = o["messageId"]?.stringValue else { return nil }
            return .init(chatId: chatId, messageId: messageId, at: Date(ms: o["seit"]?.intValue ?? 0))
        }

        var transparency: [String: TransparencyChain] = [:]
        for (slot, text) in store where slot.hasPrefix("kt_log_") {
            let uid = String(slot.dropFirst("kt_log_".count))
            let entries = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])?
                .compactMap { try? KeyCommitment(json: JSONObject(any: $0)) } ?? []
            guard !entries.isEmpty else { continue }
            let pin = store["kt_pin_\(uid)"].flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) as? String }
            transparency[uid] = TransparencyChain(entries: entries, signingPin: pin.flatMap(Data.init(base64:)))
        }

        return Result(
            userId: userId, identity: identity, settings: settings,
            contacts: contacts, chats: chats, messages: messages, ratchets: ratchets,
            preKeys: preKeys(object(store["prekey_state"])),
            counters: counters(object(store["control_counters"])),
            transparency: transparency, meta: meta
        )
    }

    /// In den Speicher der Engine schreiben — dieselben Slots, die sie liest.
    public static func write(_ r: Result, to vault: Vault) {
        vault.saveValue(r.contacts, slot: "contacts")
        vault.saveValue(r.chats, slot: "chats")
        for (chatId, list) in r.messages { vault.saveValue(list, slot: "messages.\(chatId)") }
        for (chatId, text) in r.ratchets { vault.saveValue(RatchetSlot(state: text, header: nil), slot: "ratchet.\(chatId)") }
        if let p = r.preKeys { vault.saveValue(p, slot: "prekeys") }
        if let c = r.counters { vault.saveValue(c, slot: "control") }
        vault.saveValue(r.meta, slot: "meta")
        let kt: JSONObject = r.transparency.mapValues { .object($0.json) }
        if let text = try? kt.jsonString() { try? vault.save(Data(text.utf8), slot: "kt") }
    }

    /// Eine Datei aus `krypta_store` öffnen. v2: [0x02][Nonce][MAC][Chiffrat]
    /// mit dem Slot als AAD; v1 (älter): ohne Kennbyte und ohne AAD. Wie in
    /// Dart wird bei v2-Fehlschlag v1 versucht — ein zufälliges erstes
    /// Nonce-Byte kann 0x02 sein, und beide Wege verlangen einen gültigen MAC.
    public static func openStoreBlob(_ blob: Data, key: Data, slot: String) -> Data? {
        let bytes = blob.detached
        if bytes.first == 0x02, let plain = try? Envelope.openLocal(bytes, key: key, slot: slot) { return plain }
        guard bytes.count >= 40 else { return nil }
        return try? Primitives.xchachaOpen(
            .init(ciphertext: bytes.subdata(in: 40..<bytes.count), nonce: bytes.subdata(in: 0..<24), mac: bytes.subdata(in: 24..<40)),
            key: key, aad: Data()
        )
    }

    // MARK: - Modelle

    static func contact(_ m: JSONObject) -> Contact? {
        guard let id = m["id"]?.stringValue, let key = m["publicKey"]?.stringValue.flatMap(Data.init(base64:)), key.count == 32 else { return nil }
        let trust: TrustState = m["trustState"]?.intValue.flatMap(trustState) ?? (m["verified"]?.intValue == 1 ? .verified : .unverified)
        let request: RequestState = m["requestState"]?.intValue.flatMap(requestState) ?? .established
        var c = Contact(id: id, publicKey: key, requestState: request, trustState: trust, now: date(m["addedAt"]) ?? Date())
        c.displayName = m["displayName"]?.stringValue ?? Contact.defaultName(for: id)
        c.trustBeforeBlock = m["trustBeforeBlock"]?.intValue.flatMap(trustState)
        c.declineCount = m["declineCount"]?.intValue ?? 0
        c.verifiedAt = date(m["verifiedAt"])
        c.verificationMethod = m["verificationMethod"]?.intValue.flatMap { [.qrCode, .safetyNumber, .manual][safe: $0] }
        c.verifiedFingerprint = m["verifiedFingerprint"]?.stringValue
        c.previousPublicKey = m["prevPubKey"]?.stringValue.flatMap(Data.init(base64:))
        c.firstSeenIdentityKey = m["firstSeenKey"]?.stringValue.flatMap(Data.init(base64:)) ?? key
        c.lastKeyChangeAt = date(m["lastKeyChangeAt"])
        c.safetyNumberVersion = m["snVersion"]?.intValue
        c.keyChangeCount = m["keyChangeCount"]?.intValue ?? 0
        c.lastVerifiedEpoch = m["ktEpoch"]?.intValue
        // Nur ein festgestellter Widerspruch zählt; „noch nicht" bleibt offen.
        c.transparencyVerified = m["ktVerified"]?.boolValue == true ? true : (m["ktEpoch"] != nil && m["ktVerified"]?.boolValue == false ? false : nil)
        c.isGone = m["gone"]?.boolValue ?? false
        c.goneAt = date(m["goneAt"])
        return c
    }

    static func chat(_ m: JSONObject) -> Chat? {
        guard let id = m["id"]?.stringValue, let recipient = m["recipientId"]?.stringValue else { return nil }
        var c = Chat(id: id, recipientId: recipient, name: m["recipientName"]?.stringValue ?? Contact.defaultName(for: recipient))
        c.lastActivity = date(m["lastMessageTime"])
        c.timer = m["defaultSelfDestructMs"]?.intValue.flatMap(SelfDestructPolicy.clamp(ms:))
        c.timerSetAt = date(m["defaultSelfDestructSetAt"])
        c.deleteAfterRead = m["sdNachLesen"]?.intValue == 1
        c.ruleVersion = m["sdVersion"]?.intValue ?? 0
        return c
    }

    static func message(_ m: JSONObject) -> Message? {
        guard let id = m["id"]?.stringValue, let chatId = m["chatId"]?.stringValue,
              let sender = m["senderId"]?.stringValue, let recipient = m["recipientId"]?.stringValue,
              let timestamp = date(m["timestamp"]) else { return nil }
        let status: MessageStatus = m["status"]?.intValue.flatMap { [.sending, .sent, .delivered, .read, .failed][safe: $0] } ?? .sent
        let pw = m["pwProtected"]?.intValue == 1
        // Eine gesperrte Passwort-Nachricht trägt den verschlüsselten Block im
        // Klartextfeld — genau so erwartet ihn die Engine.
        var msg = Message(id: id, chatId: chatId, senderId: sender, recipientId: recipient,
                          text: m["decryptedContent"]?.stringValue, timestamp: timestamp,
                          // Was beim Update noch unterwegs war, kommt nicht mehr an.
                          status: status == .sending ? .failed : status)
        msg.deliveredAt = date(m["deliveredAt"])
        msg.readAt = date(m["readAt"])
        msg.selfDestruct = m["selfDestructMs"]?.intValue.flatMap(SelfDestructPolicy.clamp(ms:))
        msg.selfDestructFromChat = m["sdFromChat"]?.boolValue ?? false
        msg.burnAfterRead = m["burnAfterRead"]?.intValue == 1
        msg.oneTime = m["einmalig"]?.intValue == 1
        msg.isPasswordProtected = pw
        msg.passwordUnlocked = !pw || m["pwUnlocked"]?.intValue == 1
        msg.systemEvent = m["sysEvent"]?.intValue.flatMap {
            [.screenshot, .screenRecording, .accountDeleted, .selfDestructChanged, .selfDestructAfterRead][safe: $0]
        }
        return msg
    }

    static func preKeys(_ m: JSONObject?) -> PreKeyStore? {
        guard let m else { return nil }
        func spk(_ v: JSONValue?) -> SignedPreKey? {
            guard let o = v?.objectValue, let id = o["id"]?.intValue,
                  let pub = o["pub"]?.stringValue.flatMap(Data.init(base64:)),
                  let priv = o["priv"]?.stringValue.flatMap(Data.init(base64:)),
                  let ts = o["ts"]?.intValue else { return nil }
            return SignedPreKey(id: id, publicKey: pub, privateKey: priv, createdAt: Date(ms: ts))
        }
        return PreKeyStore(current: spk(m["spk"]), previous: (m["prevSpks"]?.arrayValue ?? []).compactMap(spk), nextId: m["nextId"]?.intValue ?? 0)
    }

    static func counters(_ m: JSONObject?) -> ControlCounter? {
        guard let m else { return nil }
        func ints(_ v: JSONValue?) -> [String: Int] { v?.objectValue?.compactMapValues(\.intValue) ?? [:] }
        return ControlCounter(sent: ints(m["counters"]), lastSeen: ints(m["lastSeen"]))
    }

    // MARK: - Hilfen

    static let trustState: (Int) -> TrustState? = { [.unverified, .verified, .keyChanged, .blocked][safe: $0] }
    static let requestState: (Int) -> RequestState? = { [.established, .outgoing, .incoming, .declined][safe: $0] }

    static func date(_ v: JSONValue?) -> Date? { v?.intValue.map { Date(ms: $0) } }

    static func list(_ text: String?) -> [JSONObject] {
        guard let text, let any = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any] else { return [] }
        return any.compactMap { ($0 as? [String: Any]).map(JSONObject.init(any:)) }
    }

    static func strings(_ text: String?) -> [String] {
        guard let text, let any = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any] else { return [] }
        return any.compactMap { $0 as? String }
    }

    static func object(_ text: String?) -> JSONObject? {
        guard let text else { return nil }
        return try? JSONObject.parse(text)
    }
}

private extension Date {
    init(ms: Int) { self.init(timeIntervalSince1970: Double(ms) / 1000) }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
