import KryptaCore
import UserNotifications

/// Macht aus der Mitteilung des Servers eine mit Absender — ohne Inhalt.
///
/// Der Server schickt immer denselben Text und in `nt` den Anhänger aus der
/// Nachricht (siehe NotificationTag). Hier wird er gegen die Schlüssel der
/// Kontakte geprüft. Passt einer, steht dort wie in Nachrichten der Name als
/// Titel und darunter „Neue Nachricht"; sonst bleibt es bei „Neue Nachricht".
/// Entschlüsselt wird nichts, und der Ratchet-Zustand der App wird nicht
/// angefasst.
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var original: UNNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        handler = contentHandler
        original = request.content
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        let tag = request.content.userInfo["nt"] as? String
        content.title = ""
        content.subtitle = ""
        switch NotificationIndexStore.load()?.resolve(tag) ?? .unknown {
        case .contact(let name?, let id):
            content.title = name
            content.body = String(localized: "Neue Nachricht")
            // Stapel je Absender, wie in Nachrichten.
            if let id { content.threadIdentifier = "chat.\(id)" }
            if let id { content.userInfo["contact"] = id }
        case .contact(nil, let id):
            content.body = String(localized: "Neue Nachricht")
            // Ohne Namen auch keine Stapel — sonst verriete ihre Zahl,
            // wie viele verschiedene Leute geschrieben haben.
            if let id { content.userInfo["contact"] = id }
        case .request:
            content.body = String(localized: "Neue Kontaktanfrage")
            content.userInfo["request"] = true
        case .unknown:
            content.body = String(localized: "Du hast eine neue Nachricht erhalten")
        }
        content.badge = NSNumber(value: NotificationIndexStore.nextBadge())
        handler = nil
        contentHandler(content)
    }

    /// Die Zeit ist um: der neutrale Text des Servers geht raus.
    override func serviceExtensionTimeWillExpire() {
        if let handler, let original { handler(original) }
        handler = nil
    }
}
