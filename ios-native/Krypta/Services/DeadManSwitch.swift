import BackgroundTasks
import Foundation

/// Totmannschalter: Wer Krypta so und so viele Tage nicht entsperrt, dessen
/// Krypta löscht sich — Schlüssel, Chats, Konto auf dem Server, Wallet.
///
/// Gedacht für den Fall, dass das iPhone weg ist (beschlagnahmt, verloren)
/// und jemand darauf wartet, es irgendwann zu öffnen. Geprüft wird:
/// - bei jedem Start und jedem Zurückkommen in die App, bevor irgendetwas
///   zu sehen ist;
/// - im Hintergrund, wenn iOS die App dafür weckt (BGAppRefreshTask). Wann
///   das passiert, entscheidet iOS; verlassen kann man sich nur auf den
///   nächsten Start.
///
/// Gemessen wird an der Uhr des iPhones. Wer die Uhr zurückstellt, schiebt
/// die Löschung hinaus; das kann nur, wer das iPhone schon entsperrt hat.
enum DeadManSwitch {
    static let taskIdentifier = "com.calcchat.ww.deadman"
    static let choices = [3, 7, 14, 30, 90]

    /// `nil`: aus.
    static var days: Int? {
        get { Keychain.string(.deadManDays).flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil } }
        set {
            if let newValue, newValue > 0 {
                Keychain.set(String(newValue), for: .deadManDays)
                recordUnlock()
            } else {
                Keychain.delete(.deadManDays)
            }
        }
    }

    static var lastUnlock: Date? {
        Keychain.string(.lastUnlock).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    /// Nach jedem Entsperren (Rechner-Code, Face ID, Passwort, oder direkt).
    static func recordUnlock(now: Date = Date()) {
        Keychain.set(String(now.timeIntervalSince1970), for: .lastUnlock)
    }

    /// Ist die Frist um?
    static func isDue(now: Date = Date()) -> Bool {
        guard let days, let last = lastUnlock else { return false }
        return now.timeIntervalSince(last) > TimeInterval(days) * 86_400
    }

    static func deadline() -> Date? {
        guard let days, let last = lastUnlock else { return nil }
        return last.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    // MARK: - Hintergrund

    /// Einmal beim Start, bevor die App fertig geladen ist.
    static func registerBackgroundTask(_ wipe: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let work = Task { @MainActor in
                if isDue() { await wipe() }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Beim Verlassen der App: iOS bitten, zur Frist nachzusehen.
    static func scheduleBackgroundCheck() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        guard let deadline = deadline() else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = max(deadline, Date().addingTimeInterval(15 * 60))
        try? BGTaskScheduler.shared.submit(request)
    }
}
