import KryptaMessenger
import UIKit
import UserNotifications

/// Mitteilungen: „Neue Nachricht von Mami", nie der Inhalt.
///
/// Der Weg: der Absender legt einen Anhänger in die Nachricht, das Abo in
/// CloudKit (`CloudKitRelay.subscribeToInbox`) schickt ihn per APNs an das
/// iPhone, und die Notification Service Extension setzt den Namen ein. Die
/// App sorgt hier nur für drei Dinge: das Abo, den Index im geteilten
/// Schlüsselbund und keine Banner, solange sie selbst vorne ist.
@MainActor
final class PushService: NSObject {
    static let shared = PushService()

    /// Vorgabe an — wie in der Flutter-Fassung.
    nonisolated static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "push.off") }
        set { UserDefaults.standard.set(!newValue, forKey: "push.off") }
    }

    /// Vorgabe an: der Name des Kontakts steht in der Mitteilung.
    nonisolated static var showsNames: Bool {
        get { !UserDefaults.standard.bool(forKey: "push.anonymous") }
        set { UserDefaults.standard.set(!newValue, forKey: "push.anonymous") }
    }

    private var userId: String?
    private let relay = CloudKitRelay()

    /// Demo-Modus und UI-Tests laufen ohne iCloud.
    private var usesCloud: Bool {
        #if DEBUG
        return !(DemoMode.isActive || DemoMode.isOffline)
        #else
        return true
        #endif
    }

    /// Wohin ein Tippen auf die Mitteilung führt.
    enum Target: Equatable {
        case chat(contactId: String)
        case requests
    }

    /// Setzt die App: wohin nach dem Tippen, und ob gerade ein Banner passt.
    var open: ((Target) -> Void)?
    var shouldPresent: ((Target?) -> Bool)?
    /// Getippt, bevor die App so weit war (Kaltstart aus der Mitteilung).
    private var pendingTarget: Target?

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Nach dem Entsperren: Erlaubnis (einmalig), Abo, Index.
    func start(userId: String, engine: MessengerEngine) async {
        self.userId = userId
        attach(engine)
        guard Self.isEnabled else { return }
        let granted = await SystemPrompt.during {
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        guard granted else { return }
        // CloudKit stellt seine Mitteilungen über die Registrierung der App zu;
        // das Token selbst braucht Krypta nicht.
        UIApplication.shared.registerForRemoteNotifications()
        await subscribe()
    }

    /// Den Index aktuell halten — braucht weder Netz noch Erlaubnis.
    func attach(_ engine: MessengerEngine) {
        engine.onContactsChanged = { [weak engine] in
            guard let engine else { return }
            PushService.shared.updateIndex(engine)
        }
        updateIndex(engine)
        clearDelivered()
    }

    /// In den Einstellungen umgeschaltet.
    func setEnabled(_ on: Bool, engine: MessengerEngine) async {
        Self.isEnabled = on
        if on {
            await start(userId: engine.userId, engine: engine)
        } else {
            if usesCloud { try? await relay.unsubscribeFromInbox() }
            UIApplication.shared.unregisterForRemoteNotifications()
        }
    }

    func updateIndex(_ engine: MessengerEngine) {
        NotificationIndexStore.save(engine.notificationIndex(showNames: Self.showsNames))
    }

    /// Notfall-Löschung: nichts bleibt zurück.
    func wipe() async {
        NotificationIndexStore.delete()
        clearDelivered()
        if usesCloud { try? await relay.unsubscribeFromInbox() }
        userId = nil
    }

    /// Beim Öffnen verschwinden die Mitteilungen vom Sperrbildschirm.
    func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().setBadgeCount(0)
        NotificationIndexStore.resetBadge()
    }

    /// Ein Chat ist offen: seine Mitteilungen braucht niemand mehr.
    func clearDelivered(contactId: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.deliveredNotifications()
                .filter { Self.target(of: $0.request.content.userInfo) == .chat(contactId: contactId) }
                .map(\.request.identifier)
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    /// Die App ist bereit: eine vorher angetippte Mitteilung jetzt öffnen.
    func deliverPendingTarget() {
        guard let target = pendingTarget, let open else { return }
        pendingTarget = nil
        open(target)
    }

    nonisolated static func target(of userInfo: [AnyHashable: Any]) -> Target? {
        if let id = userInfo["contact"] as? String, !id.isEmpty { return .chat(contactId: id) }
        if userInfo["request"] as? Bool == true { return .requests }
        return nil
    }

    private func subscribe() async {
        guard let userId, Self.isEnabled, usesCloud else { return }
        try? await relay.subscribeToInbox(uid: userId)
    }
}

extension PushService: @preconcurrency UNUserNotificationCenterDelegate {
    /// Ist die App vorne, zeigt sie ein Banner nur, wenn die Chats offen
    /// sind und die Nachricht aus einem anderen Chat kommt — wie Nachrichten.
    /// Über dem Rechner oder der Sperre hat ein Banner nichts zu suchen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let target = Self.target(of: notification.request.content.userInfo)
        // Etwas ist angekommen: gleich abholen, nicht erst beim nächsten Takt.
        InboxWake.shared.poke()
        // Die Extension hat schon mitgezählt; wer in der App ist, sieht es.
        NotificationIndexStore.resetBadge()
        guard shouldPresent?(target) == true else { return [] }
        return [.banner, .list, .sound]
    }

    /// Angetippt: nach dem Entsperren direkt in den Chat.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let target = Self.target(of: response.notification.request.content.userInfo) else { return }
        if let open {
            open(target)
        } else {
            pendingTarget = target
        }
    }
}

/// Nur für das, was SwiftUI nicht selbst kann.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Keine Tastaturen von Drittanbietern: sie sähen jeden getippten
    /// Buchstaben, und manche schicken ihn in die Cloud. In Krypta tippt
    /// man immer mit der Tastatur von Apple.
    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
