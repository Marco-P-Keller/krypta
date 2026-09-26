import Foundation

/// Nach dem Empfang bleibt nichts auf dem Server.
///
/// Drei Riegel, jeder für sich genug:
/// 1. Der Empfänger löscht jede Nachricht, sobald er sie abgeholt hat —
///    auch unlesbare oder abgelehnte — und versucht es erneut, wenn der
///    Server nicht antwortet. Schlägt alles fehl, liefert der Server sie beim
///    nächsten Start noch einmal; sie wird als Duplikat erkannt und gelöscht.
/// 2. Der Absender merkt sich, wo seine Nachricht liegt, und löscht sie
///    selbst, sobald die Zustellung gemeldet ist.
/// 3. Was nie abgeholt wird, räumt der Server nach 24 Stunden weg
///    (`cleanupExpiredMessages` in firebase/functions/index.js).
struct ServerCopy: Codable, Equatable {
    let to: String
    let docId: String
    let at: Date
    /// Versiegelt gesendet: gelöscht wird dann ebenfalls ohne Anmeldung.
    var sealed: Bool?
}

extension MessengerEngine {
    static let maxServerCopies = 1000
    /// Länger als der Server sie aufhebt, braucht sich niemand zu merken.
    static let serverCopyLifetime: TimeInterval = 25 * 3600

    func loadServerCopies() {
        let now = Date()
        serverCopies = (vault.loadValue([String: ServerCopy].self, slot: "servercopies") ?? [:])
            .filter { now.timeIntervalSince($0.value.at) < Self.serverCopyLifetime }
    }

    func saveServerCopies() { vault.saveValue(serverCopies, slot: "servercopies") }

    /// Empfänger: die abgeholte Nachricht vom Server löschen, mit bis zu drei
    /// Versuchen.
    func purgeFromInbox(_ docId: String) {
        Task { [relay, userId] in
            for attempt in 0..<3 {
                do {
                    try await relay.deleteFromInbox(uid: userId, docId: docId)
                    return
                } catch {
                    try? await Task.sleep(for: .seconds(Double(1 << attempt)))
                }
            }
        }
    }

    /// Absender: wo die gerade gesendete Nachricht auf dem Server liegt.
    func rememberServerCopy(messageId: String, to: String, delivery: Delivery) {
        serverCopies[messageId] = ServerCopy(to: to, docId: delivery.docId, at: Date(), sealed: delivery.sealed)
        if serverCopies.count > Self.maxServerCopies {
            let oldest = serverCopies.sorted { $0.value.at < $1.value.at }.prefix(serverCopies.count - Self.maxServerCopies)
            for (id, _) in oldest { serverCopies.removeValue(forKey: id) }
        }
        saveServerCopies()
    }

    /// Absender: die Zustellung ist gemeldet — die eigene Kopie auf dem
    /// Server löschen, falls der Empfänger es nicht schon getan hat.
    func retractServerCopy(messageId: String) {
        guard let copy = serverCopies.removeValue(forKey: messageId) else { return }
        saveServerCopies()
        Task { [relay] in
            if copy.sealed == true {
                try? await relay.retractSealed(to: copy.to, docId: copy.docId)
            } else {
                try? await relay.retract(to: copy.to, docId: copy.docId)
            }
        }
    }
}
