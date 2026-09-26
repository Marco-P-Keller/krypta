import Foundation

/// Merkt sich eine begonnene Notfall-Löschung, damit ein Beenden der App
/// mittendrin sie nicht aufhält: der nächste Start bringt sie zu Ende.
enum EmergencyWipe {
    private static let pendingKey = "wipe.pending"
    private static let userKey = "wipe.uid"

    static var isPending: Bool { UserDefaults.standard.bool(forKey: pendingKey) }
    static var pendingUserId: String? { UserDefaults.standard.string(forKey: userKey) }

    static func markPending(userId: String?) {
        UserDefaults.standard.set(true, forKey: pendingKey)
        UserDefaults.standard.set(userId, forKey: userKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    /// Wartet auf `work`, aber höchstens `seconds` — was dann noch läuft,
    /// läuft im Hintergrund weiter.
    @MainActor
    static func withDeadline(seconds: Double, _ work: @escaping @MainActor () async -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = Gate(continuation)
            Task { @MainActor in
                await work()
                gate.open()
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                gate.open()
            }
        }
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
        func open() {
            lock.withLock {
                continuation?.resume()
                continuation = nil
            }
        }
    }
}
