import Foundation
import KryptaCore

/// Eine Nachricht im Posteingang auf dem Server.
///
/// Versiegelt (`sealed`) kennt der Server weder Absender noch Kennung;
/// `senderId`, `messageId` und `payload` stehen dann erst nach dem Öffnen fest.
public struct InboxEnvelope: Sendable, Equatable {
    public let docId: String
    public let senderId: String
    public let messageId: String
    public let payload: JSONObject
    public let sealed: Data?

    public init(docId: String, senderId: String, messageId: String, payload: JSONObject, sealed: Data? = nil) {
        self.docId = docId
        self.senderId = senderId
        self.messageId = messageId
        self.payload = payload
        self.sealed = sealed
    }
}

public enum RelayError: Error, Equatable {
    /// Der Server lehnt ab — beim versiegelten Senden: der Zustellschlüssel
    /// ist veraltet, oder die neuen Regeln sind noch nicht ausgerollt.
    case accessDenied
}

/// Der Server — in der App Firestore, in Tests ein Wörterbuch.
///
/// Dieselben Sammlungen wie die Flutter-Fassung: `publicKeys`, `prekeys`,
/// `deliveryTokens`, `messages/{uid}/inbox`.
public protocol Relay: AnyObject, Sendable {
    func publishPublicKey(uid: String, publicKey: String) async throws
    func publicKey(uid: String) async throws -> String?
    func publishPreKeyBundle(uid: String, bundle: JSONObject) async throws
    func preKeyBundle(uid: String) async throws -> JSONObject?
    func publishDeliveryToken(uid: String, token: String) async throws
    /// Legt die Nachricht in den Posteingang von `to`; gibt die Kennung des Dokuments zurück.
    @discardableResult
    func send(from: String, to: String, messageId: String, payload: JSONObject) async throws -> String
    /// Neu eingetroffene Nachrichten, in Serverreihenfolge.
    func inbox(uid: String) -> AsyncThrowingStream<[InboxEnvelope], Error>
    func deleteFromInbox(uid: String, docId: String) async throws
    /// Der Absender löscht seine eigene Nachricht aus dem Posteingang von `to`.
    func retract(to: String, docId: String) async throws
    /// Sealed Sender: nur der SHA-256 des eigenen Zustellschlüssels liegt auf dem Server.
    func publishSealedAccess(uid: String, keyHash: Data) async throws
    /// Versiegelt und ohne Anmeldung in den Posteingang von `to`. Der Server
    /// sieht nur Empfängerin, Zeit, Größe und den Anhänger für die Mitteilung.
    /// Wirft `RelayError.accessDenied`, wenn der Schlüssel nicht passt.
    @discardableResult
    func sendSealed(to: String, accessKey: Data, envelope: Data, tag: String?) async throws -> String
    /// Die eigene versiegelte Nachricht wieder löschen, ebenfalls ohne Anmeldung.
    func retractSealed(to: String, docId: String) async throws
    func deleteAllUserData(uid: String) async throws
    /// Key Transparency: `keyCommitments/{uid}/log/{epoch}`.
    func publishKeyCommitment(uid: String, commitment: JSONObject, epoch: Int) async throws
    /// Einträge nach Epoche sortiert; mit `since` nur die danach.
    func keyCommitments(uid: String, since: Int?) async throws -> [JSONObject]
}

/// Verschlüsselter lokaler Speicher, pro Slot ein Blob.
public protocol Vault: AnyObject, Sendable {
    func load(_ slot: String) throws -> Data?
    func save(_ data: Data, slot: String) throws
    func delete(_ slot: String) throws
    func wipe() throws
}

extension Vault {
    func loadValue<T: Decodable>(_ type: T.Type, slot: String) -> T? {
        guard let data = try? load(slot) else { return nil }
        return try? JSONDecoder.krypta.decode(T.self, from: data)
    }

    func saveValue<T: Encodable>(_ value: T, slot: String) {
        guard let data = try? JSONEncoder.krypta.encode(value) else { return }
        try? save(data, slot: slot)
    }
}

extension JSONEncoder {
    static let krypta: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.dataEncodingStrategy = .base64
        return e
    }()
}

extension JSONDecoder {
    static let krypta: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        d.dataDecodingStrategy = .base64
        return d
    }()
}

// MARK: - In-Memory-Fassungen (Tests, Vorschauen)

public final class MemoryVault: Vault, @unchecked Sendable {
    private var slots: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func load(_ slot: String) throws -> Data? { lock.withLock { slots[slot] } }
    public func save(_ data: Data, slot: String) throws { lock.withLock { slots[slot] = data } }
    public func delete(_ slot: String) throws { _ = lock.withLock { slots.removeValue(forKey: slot) } }
    public func wipe() throws { lock.withLock { slots.removeAll() } }
    public var slotNames: [String] { lock.withLock { Array(slots.keys) } }
}

/// Ein Server im Speicher, gegen den mehrere Engines laufen können.
public final class MemoryRelay: Relay, @unchecked Sendable {
    private let lock = NSLock()
    private var publicKeys: [String: String] = [:]
    private var bundles: [String: JSONObject] = [:]
    private var tokens: [String: String] = [:]
    private var sealedAccess: [String: Data] = [:]
    private var inboxes: [String: [InboxEnvelope]] = [:]
    private var commitments: [String: [Int: JSONObject]] = [:]
    private var listeners: [String: AsyncThrowingStream<[InboxEnvelope], Error>.Continuation] = [:]
    public private(set) var sentCount = 0
    /// Für Tests: jede gesendete Nutzlast mit Empfänger — so, wie der Server
    /// sie sieht (versiegelt nur `s` und `nt`).
    public private(set) var sentPayloads: [(to: String, payload: JSONObject)] = []
    /// Für Tests: wie viele Nachrichten versiegelt ankamen.
    public private(set) var sealedCount = 0
    /// Für Tests: der Server kennt die Regeln für Sealed Sender noch nicht.
    public var rejectSealed = false
    /// Für Tests: schlägt jedes Senden fehl, solange `true`.
    public var failSends = false
    /// Für Tests: bei diesen Empfängern schlägt das Löschen aus dem Posteingang fehl.
    public var failInboxDeletes: Set<String> = []

    public init() {}

    public func publishPublicKey(uid: String, publicKey: String) async throws { lock.withLock { publicKeys[uid] = publicKey } }
    public func publicKey(uid: String) async throws -> String? { lock.withLock { publicKeys[uid] } }
    public func publishPreKeyBundle(uid: String, bundle: JSONObject) async throws { lock.withLock { bundles[uid] = bundle } }
    public func preKeyBundle(uid: String) async throws -> JSONObject? { lock.withLock { bundles[uid] } }
    public func publishDeliveryToken(uid: String, token: String) async throws { lock.withLock { tokens[uid] = token } }

    struct Offline: Error {}

    @discardableResult
    public func send(from: String, to: String, messageId: String, payload: JSONObject) async throws -> String {
        let (envelope, listener): (InboxEnvelope, AsyncThrowingStream<[InboxEnvelope], Error>.Continuation?) = try lock.withLock {
            if failSends { throw Offline() }
            sentCount += 1
            sentPayloads.append((to, payload))
            let env = InboxEnvelope(docId: UUID().uuidString, senderId: from, messageId: messageId, payload: payload)
            inboxes[to, default: []].append(env)
            return (env, listeners[to])
        }
        listener?.yield([envelope])
        return envelope.docId
    }

    public func publishSealedAccess(uid: String, keyHash: Data) async throws {
        lock.withLock { sealedAccess[uid] = keyHash }
    }

    /// Wie die Regel in Firestore: SHA-256(Schlüssel) muss zum Eintrag passen.
    @discardableResult
    public func sendSealed(to: String, accessKey: Data, envelope: Data, tag: String?) async throws -> String {
        let (env, listener): (InboxEnvelope, AsyncThrowingStream<[InboxEnvelope], Error>.Continuation?) = try lock.withLock {
            if failSends { throw Offline() }
            guard !rejectSealed, let hash = sealedAccess[to], SealedSender.accessKeyHash(accessKey) == hash else {
                throw RelayError.accessDenied
            }
            sentCount += 1
            sealedCount += 1
            var seen: JSONObject = ["s": .string(envelope.base64)]
            if let tag { seen["nt"] = .string(tag) }
            sentPayloads.append((to, seen))
            let env = InboxEnvelope(docId: UUID().uuidString, senderId: "", messageId: "", payload: [:], sealed: envelope)
            inboxes[to, default: []].append(env)
            return (env, listeners[to])
        }
        listener?.yield([env])
        return env.docId
    }

    public func retractSealed(to: String, docId: String) async throws {
        lock.withLock { inboxes[to]?.removeAll { $0.docId == docId && $0.sealed != nil } }
    }

    public func inbox(uid: String) -> AsyncThrowingStream<[InboxEnvelope], Error> {
        AsyncThrowingStream { continuation in
            let pending: [InboxEnvelope] = lock.withLock {
                listeners[uid] = continuation
                return inboxes[uid] ?? []
            }
            if !pending.isEmpty { continuation.yield(pending) }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.listeners.removeValue(forKey: uid) }
            }
        }
    }

    public func deleteFromInbox(uid: String, docId: String) async throws {
        try lock.withLock {
            if failInboxDeletes.contains(uid) { throw Offline() }
            inboxes[uid]?.removeAll { $0.docId == docId }
        }
    }

    public func retract(to: String, docId: String) async throws {
        lock.withLock { inboxes[to]?.removeAll { $0.docId == docId } }
    }

    public func deleteAllUserData(uid: String) async throws {
        lock.withLock {
            publicKeys.removeValue(forKey: uid)
            bundles.removeValue(forKey: uid)
            tokens.removeValue(forKey: uid)
            sealedAccess.removeValue(forKey: uid)
            inboxes.removeValue(forKey: uid)
            commitments.removeValue(forKey: uid)
        }
    }

    public func publishKeyCommitment(uid: String, commitment: JSONObject, epoch: Int) async throws {
        try lock.withLock {
            // Wie die Regel in Firestore: nur anlegen, nie überschreiben.
            if commitments[uid]?[epoch] != nil { throw Offline() }
            commitments[uid, default: [:]][epoch] = commitment
        }
    }

    public func keyCommitments(uid: String, since: Int?) async throws -> [JSONObject] {
        lock.withLock {
            (commitments[uid] ?? [:]).filter { since == nil || $0.key > since! }.sorted { $0.key < $1.key }.map(\.value)
        }
    }

    /// Für Tests: der Server tauscht einen Eintrag aus (Split View).
    public func forgeKeyCommitment(uid: String, epoch: Int, _ commitment: JSONObject) {
        lock.withLock { commitments[uid, default: [:]][epoch] = commitment }
    }

    /// Wie viele Nachrichten noch im Posteingang liegen.
    public func pending(for uid: String) -> Int { lock.withLock { inboxes[uid]?.count ?? 0 } }

    /// Für Tests: der Server spielt eine Nachricht absichtlich erneut ein.
    public func replay(_ envelope: InboxEnvelope, to uid: String) {
        let listener = lock.withLock { () -> AsyncThrowingStream<[InboxEnvelope], Error>.Continuation? in
            let copy = InboxEnvelope(docId: UUID().uuidString, senderId: envelope.senderId, messageId: envelope.messageId, payload: envelope.payload, sealed: envelope.sealed)
            inboxes[uid, default: []].append(copy)
            return listeners[uid]
        }
        listener?.yield(lock.withLock { inboxes[uid]?.suffix(1).map { $0 } ?? [] })
    }

    /// Für Tests: alles, was je an `uid` ging und noch da ist.
    public func inboxSnapshot(_ uid: String) -> [InboxEnvelope] { lock.withLock { inboxes[uid] ?? [] } }
}
