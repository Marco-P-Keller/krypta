import Foundation
import Observation
import KryptaCore

/// Stellschrauben, die Tests anders brauchen als die App.
public struct EngineConfig: Sendable {
    /// Streuung für Zustell-, Lese- und Ablaufmeldungen (Sekunden). Nimmt
    /// den Meldungen die zeitliche Genauigkeit.
    public var ackJitter: ClosedRange<Double>
    /// Wie lange Meldungen beim Löschen oder Zurücksetzen höchstens warten.
    public var announceTimeout: TimeInterval
    /// Takt der Ablaufuhr.
    public var tick: TimeInterval

    public init(ackJitter: ClosedRange<Double> = 0.3...2.0, announceTimeout: TimeInterval = 3, tick: TimeInterval = 1) {
        self.ackJitter = ackJitter
        self.announceTimeout = announceTimeout
        self.tick = tick
    }

    public static let immediate = EngineConfig(ackJitter: 0...0, announceTimeout: 3, tick: 0.2)
}

/// Was die Engine über Neustarts hinweg behält, ohne dass es zu einem
/// Kontakt, Chat oder einer Sitzung gehört.
struct EngineMeta: Codable {
    /// Handschlag-Ephemerals, die schon angenommen wurden (je Chat, begrenzt).
    var acceptedEks: [String: [String]] = [:]
    /// `_psid`-Spur je Kontakt — überlebt das Verwerfen einer Sitzung.
    var psidLineage: [String: [String]] = [:]
    /// Zuletzt verarbeitete Nachrichtenkennungen (Duplikate).
    var processedIds: [String] = []
    /// Ablaufmeldungen, die noch an die Gegenseite müssen.
    var pendingBurns: [PendingBurn] = []
    /// Fehlversuche beim Entsperren von Passwort-Nachrichten.
    var unlockAttempts: [String: UnlockAttempt] = [:]
    var readReceipts = false
    var chatPreview = true
    /// Sealed Sender: der eigene Zustellschlüssel (Engine+Sealed).
    var sealedAccessKey: Data?

    struct PendingBurn: Codable, Equatable {
        let chatId: String
        let messageId: String
        let at: Date
    }

    struct UnlockAttempt: Codable {
        var fails: Int
        var last: Date
    }
}

/// Gespeicherte Sitzung: Ratchet-Zustand und — bis der Server die erste
/// Nachricht angenommen hat — der X3DH-Kopf dazu.
struct RatchetSlot: Codable {
    var state: String
    var header: String?
}

public enum AddContactResult: Equatable, Sendable {
    case added(Contact)
    case notFound
    case invalidId
    case isSelf
}

public enum QRAddResult: Equatable, Sendable {
    case verified(Contact)
    case keyMismatch
    case notFound
}

/// Der Messenger: Kontakte, Chats, Senden, Empfangen.
///
/// Spiegelt features/messenger/logic/messenger_provider.dart. Die Regeln
/// sind dieselben; die Namen der Policies stehen in den Kommentaren, damit
/// man die Stelle drüben findet.
///
/// Nebenläufigkeit: alles läuft auf dem Main Actor, und jeder Ratchet-
/// Schritt (lesen, rechnen, zurückschreiben) steht ohne `await` dazwischen.
/// Zwei Vorgänge können sich damit nie an einem Kettenschlüssel treffen.
/// Was an einem Chat sendet, läuft zusätzlich durch eine Warteschlange,
/// damit der Sitzungsaufbau (mit Netzabfragen) nicht doppelt passiert.
@MainActor
@Observable
public final class MessengerEngine {
    public let userId: String
    public let identity: KeyPair

    public internal(set) var contacts: [Contact] = []
    public internal(set) var chats: [Chat] = []
    public internal(set) var messages: [String: [Message]] = [:]
    /// `nil` solange unbekannt, danach ob Schlüssel und Bündel draußen sind.
    public internal(set) var keysPublished: Bool?
    public internal(set) var isRunning = false

    public var readReceiptsEnabled: Bool {
        get { meta.readReceipts }
        set { meta.readReceipts = newValue; saveMeta() }
    }

    public var chatPreviewEnabled: Bool {
        get { meta.chatPreview }
        set { meta.chatPreview = newValue; saveMeta() }
    }

    /// Wird von der App gesetzt: welcher Chat offen ist und ob sie vorne ist.
    public internal(set) var activeChatId: String?
    public var isForeground = true

    @ObservationIgnored let relay: Relay
    @ObservationIgnored let vault: Vault
    @ObservationIgnored let config: EngineConfig

    @ObservationIgnored var meta = EngineMeta()
    /// Eigene Nachrichten, die noch auf dem Server liegen könnten (Kennung → Ort).
    @ObservationIgnored var serverCopies: [String: ServerCopy] = [:]
    @ObservationIgnored var ratchets: [String: RatchetState] = [:]
    @ObservationIgnored var pendingHeaders: [String: JSONObject] = [:]
    @ObservationIgnored var pendingHeals: [String: RatchetState] = [:]
    @ObservationIgnored var preKeys = PreKeyStore()
    @ObservationIgnored var counters = ControlCounter()
    @ObservationIgnored var hmacKeys: [String: Data] = [:]
    @ObservationIgnored var qrTokens: [String: Date] = [:]
    @ObservationIgnored var deletingChats: Set<String> = []
    @ObservationIgnored var lastChatGone: [String: Date] = [:]
    @ObservationIgnored var burnsInFlight: Set<String> = []
    @ObservationIgnored var unlockInFlight: Set<String> = []
    @ObservationIgnored var sendQueues: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var inboxTask: Task<Void, Never>?
    @ObservationIgnored var timerTask: Task<Void, Never>?
    @ObservationIgnored var jitterTasks: [Task<Void, Never>] = []
    @ObservationIgnored var transparency: [String: TransparencyChain] = [:]
    /// Wann der Server versiegeltes Senden an einen Kontakt zuletzt abgelehnt hat.
    @ObservationIgnored var sealedDeniedAt: [String: Date] = [:]

    /// Meldet jede gespeicherte Änderung an den Kontakten — die App hält
    /// damit den Index für die Mitteilungen aktuell.
    @ObservationIgnored public var onContactsChanged: (@MainActor () -> Void)?

    static let maxAcceptedEks = 100
    static let maxProcessedIds = 1000
    static let maxLineage = 20
    static let qrTokenLifetime: TimeInterval = 10 * 60
    static let chatGoneBrake: TimeInterval = 60
    static let maxUnlockAttempts = 5
    static let unlockCooldown: TimeInterval = 30
    static let pendingBurnMaxAge: TimeInterval = 30 * 24 * 3600

    public init(userId: String, identity: KeyPair, relay: Relay, vault: Vault, config: EngineConfig = EngineConfig()) {
        self.userId = userId
        self.identity = identity
        self.relay = relay
        self.vault = vault
        self.config = config
        load()
    }

    // MARK: - Lesen für die Oberfläche

    public func contact(_ id: String) -> Contact? { contacts.first { $0.id == id } }
    public func chat(_ id: String) -> Chat? { chats.first { $0.id == id } }
    public func chat(forContact id: String) -> Chat? { chats.first { $0.recipientId == id } }
    public func messages(in chatId: String) -> [Message] { messages[chatId] ?? [] }

    /// Chats, neueste oben. Offene Anfragen an mich stehen nicht hier,
    /// sondern in `incomingRequests`.
    public var sortedChats: [Chat] {
        chats
            .filter { contact($0.recipientId)?.requestState != .incoming }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }

    public var incomingRequests: [Contact] { contacts.filter { $0.requestState == .incoming } }

    /// Ungelesen: Nachrichten der Gegenseite ohne Lesezeitpunkt.
    public func unreadCount(_ chatId: String) -> Int {
        messages(in: chatId).filter { $0.senderId != userId && $0.readAt == nil }.count
    }

    public func lastMessage(_ chatId: String) -> Message? { messages[chatId]?.last }

    public func safetyNumber(for contactId: String) -> String? {
        guard let c = contact(contactId) else { return nil }
        return SafetyNumber.generate(localUserId: userId, localIdentity: identity.publicKey, remoteUserId: c.id, remoteIdentity: c.publicKey)
    }

    public var myQRPayload: QRPayload {
        QRPayload(userId: userId, publicKey: identity.publicKey, requestToken: issueQRToken(), accessKey: sealedAccessKey)
    }

    // MARK: - Laden und Speichern

    func load() {
        meta = vault.loadValue(EngineMeta.self, slot: "meta") ?? EngineMeta()
        contacts = vault.loadValue([Contact].self, slot: "contacts") ?? []
        chats = vault.loadValue([Chat].self, slot: "chats") ?? []
        preKeys = vault.loadValue(PreKeyStore.self, slot: "prekeys") ?? PreKeyStore()
        counters = vault.loadValue(ControlCounter.self, slot: "control") ?? ControlCounter()
        loadTransparency()
        loadServerCopies()
        for chat in chats {
            messages[chat.id] = vault.loadValue([Message].self, slot: "messages.\(chat.id)") ?? []
            if let slot = vault.loadValue(RatchetSlot.self, slot: "ratchet.\(chat.id)"),
               let map = try? JSONObject.parse(slot.state),
               let state = try? RatchetState(json: map) {
                ratchets[chat.id] = state
                if let h = slot.header, let header = try? JSONObject.parse(h) { pendingHeaders[chat.id] = header }
            }
        }
    }

    func saveContacts() {
        vault.saveValue(contacts, slot: "contacts")
        onContactsChanged?()
    }
    func saveChats() {
        vault.saveValue(chats, slot: "chats")
        // Der Name in der Mitteilung ist der Chatname.
        onContactsChanged?()
    }
    func saveMessages(_ chatId: String) { vault.saveValue(messages[chatId] ?? [], slot: "messages.\(chatId)") }
    func saveMeta() { vault.saveValue(meta, slot: "meta") }
    func savePreKeys() { vault.saveValue(preKeys, slot: "prekeys") }
    func saveCounters() { vault.saveValue(counters, slot: "control") }

    func saveRatchet(_ chatId: String) {
        guard let state = ratchets[chatId], let text = try? state.json.jsonString() else {
            try? vault.delete("ratchet.\(chatId)")
            return
        }
        let header = pendingHeaders[chatId].flatMap { try? $0.jsonString() }
        vault.saveValue(RatchetSlot(state: text, header: header), slot: "ratchet.\(chatId)")
    }

    func setRatchet(_ state: RatchetState?, for chatId: String) {
        ratchets[chatId] = state
        if state == nil { pendingHeaders.removeValue(forKey: chatId) }
        saveRatchet(chatId)
    }

    func updateContact(_ id: String, _ change: (inout Contact) -> Void) {
        guard let i = contacts.firstIndex(where: { $0.id == id }) else { return }
        change(&contacts[i])
        saveContacts()
    }

    func updateChat(_ id: String, _ change: (inout Chat) -> Void) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        change(&chats[i])
        saveChats()
    }

    func updateMessage(_ chatId: String, _ messageId: String, _ change: (inout Message) -> Void) {
        guard let i = messages[chatId]?.firstIndex(where: { $0.id == messageId }) else { return }
        change(&messages[chatId]![i])
        saveMessages(chatId)
    }

    /// Findet eine Nachricht in allen Chats (Steuernachrichten tragen die
    /// Chat-Kennung der Gegenseite, nicht meine).
    func locate(_ messageId: String) -> (chatId: String, index: Int)? {
        for (chatId, list) in messages {
            if let i = list.firstIndex(where: { $0.id == messageId }) { return (chatId, i) }
        }
        return nil
    }

    func append(_ message: Message, to chatId: String) {
        messages[chatId, default: []].append(message)
        saveMessages(chatId)
        touch(chatId, message.timestamp)
    }

    func touch(_ chatId: String, _ time: Date) {
        updateChat(chatId) { $0.lastActivity = max($0.lastActivity ?? .distantPast, time) }
    }

    @discardableResult
    func chatFor(_ contact: Contact) -> Chat {
        if let existing = chat(forContact: contact.id) { return existing }
        let chat = Chat(recipientId: contact.id, name: contact.displayName)
        chats.append(chat)
        messages[chat.id] = []
        saveChats()
        return chat
    }

    func markProcessed(_ id: String) {
        meta.processedIds.append(id)
        if meta.processedIds.count > Self.maxProcessedIds {
            meta.processedIds.removeFirst(meta.processedIds.count - Self.maxProcessedIds)
        }
        saveMeta()
    }

    // MARK: - Start und Stopp

    /// Schlüssel veröffentlichen, Posteingang öffnen, Uhr starten.
    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        cleanupExpired(includeBurned: true)
        await publishKeys()
        guard isRunning else { return }
        startInbox()
        startTimer()
        retryPendingBurns()
        verifyAllTransparency()
    }

    /// Hintergrund: Empfang und Uhr anhalten. Offene Meldungen bleiben liegen.
    public func stop() {
        isRunning = false
        inboxTask?.cancel()
        inboxTask = nil
        timerTask?.cancel()
        timerTask = nil
    }

    func publishKeys() async {
        if preKeys.needsRotation() {
            _ = preKeys.rotate()
            savePreKeys()
        }
        // Ab iOS 26 gehört zu jedem Vorabschlüssel ein ML-KEM-Schlüssel.
        if preKeys.ensurePostQuantum() { savePreKeys() }
        var ok = true
        do {
            try await relay.publishPublicKey(uid: userId, publicKey: identity.publicKey.base64)
        } catch { ok = false }
        do {
            try await relay.publishPreKeyBundle(uid: userId, bundle: try preKeys.bundle(identity: identity).json)
        } catch { ok = false }
        // Das Zustell-Token für Sealed Sender: Flutter-Absender holen es sich.
        try? await relay.publishDeliveryToken(uid: userId, token: Data.random(count: 32).base64)
        await publishSealedAccess()
        keysPublished = ok
        await syncOwnTransparency()
    }

    func startInbox() {
        inboxTask?.cancel()
        let stream = relay.inbox(uid: userId)
        inboxTask = Task { [weak self] in
            var attempt = 0
            var current: AsyncThrowingStream<[InboxEnvelope], Error>? = stream
            while !Task.isCancelled {
                do {
                    guard let s = current else { break }
                    for try await batch in s {
                        attempt = 0
                        guard let self else { return }
                        for envelope in batch {
                            await self.receive(envelope)
                        }
                    }
                    // Sauber geschlossen (Serverwechsel): nach einer Sekunde neu.
                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    return
                } catch {
                    // Treppe wie InboxReconnectBackoff: 1, 2, 4 … höchstens 60 s.
                    attempt += 1
                    let wait = min(60, pow(2, Double(attempt - 1)))
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard let self, self.isRunning else { return }
                current = self.relay.inbox(uid: self.userId)
            }
        }
    }

    func startTimer() {
        timerTask?.cancel()
        let tick = config.tick
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(tick))
                guard let self else { return }
                self.cleanupExpired(includeBurned: false)
            }
        }
    }

    /// Führt `op` nach der eingestellten Streuung aus.
    func later(_ op: @escaping @MainActor () async -> Void) {
        let delay = Double.random(in: config.ackJitter)
        jitterTasks.removeAll { $0.isCancelled }
        jitterTasks.append(Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            await op()
        })
    }

    /// Wartet, bis alles Gestreute raus ist — für Tests.
    public func settle() async {
        while !jitterTasks.isEmpty {
            let tasks = jitterTasks
            jitterTasks.removeAll()
            for t in tasks { await t.value }
        }
        for q in sendQueues.values { await q.value }
    }

    /// Serialisiert alles, was an einem Chat sendet.
    func enqueue(_ chatId: String, _ op: @escaping @MainActor () async -> Void) async {
        let previous = sendQueues[chatId]
        let task = Task { @MainActor in
            await previous?.value
            await op()
        }
        sendQueues[chatId] = task
        await task.value
    }
}
