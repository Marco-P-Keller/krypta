import FirebaseMessaging
import KryptaMessenger
import UIKit
import UserNotifications

/// Mitteilungen: „Neue Nachricht von Mami", nie der Inhalt.
///
/// Der Weg: der Absender legt einen Anhänger in die Nachricht, die Cloud
/// Function (firebase/functions/index.js) reicht ihn per FCM an das iPhone,
/// und die Notification Service Extension setzt den Namen ein. Die App
/// sorgt hier nur für drei Dinge: das FCM-Token beim Server, den Index im
/// geteilten Schlüsselbund und keine Banner, solange sie selbst vorne ist.
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
    private let relay = FirebaseRelay()

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
        Messaging.messaging().delegate = self
    }

    /// Nach dem Entsperren: Erlaubnis (einmalig), Token, Index.
    func start(userId: String, engine: MessengerEngine) async {
        self.userId = userId
        attach(engine)
        guard Self.isEnabled else { return }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await uploadToken()
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
            try? await relay.deletePushToken(uid: engine.userId)
            try? await Messaging.messaging().deleteToken()
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
        try? await Messaging.messaging().deleteToken()
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

    private func uploadToken() async {
        guard let userId, Self.isEnabled, let token = try? await Messaging.messaging().token() else { return }
        try? await relay.registerPushToken(uid: userId, token: token)
    }

    func didRegister(deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Task { await uploadToken() }
    }
}

extension PushService: @preconcurrency UNUserNotificationCenterDelegate {
    /// Ist die App vorne, zeigt sie ein Banner nur, wenn die Chats offen
    /// sind und die Nachricht aus einem anderen Chat kommt — wie Nachrichten.
    /// Über dem Rechner oder der Sperre hat ein Banner nichts zu suchen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let target = Self.target(of: notification.request.content.userInfo)
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

extension PushService: @preconcurrency MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { await uploadToken() }
    }
}

/// Nur für das APNs-Token; alles andere läuft über SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushService.shared.didRegister(deviceToken: deviceToken) }
    }
}
