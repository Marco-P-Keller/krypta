import KryptaCore
import UserNotifications

/// Macht aus der Mitteilung des Servers eine mit Absender — ohne Inhalt.
///
/// Der Server schickt immer denselben Text und in `nt` den Anhänger aus der
/// Nachricht (siehe NotificationTag). Hier wird er gegen die Schlüssel der
/// Kontakte geprüft. Passt einer, steht dort „Neue Nachricht von Mami";
/// sonst bleibt es bei „Neue Nachricht". Entschlüsselt wird nichts, und der
/// Ratchet-Zustand der App wird nicht angefasst.
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
        case .contact(let name?):
            content.body = String(localized: "Neue Nachricht von \(name)")
        case .contact(nil):
            content.body = String(localized: "Neue Nachricht")
        case .request:
            content.body = String(localized: "Neue Kontaktanfrage")
        case .unknown:
            content.body = String(localized: "Du hast eine neue Nachricht erhalten")
        }
        handler = nil
        contentHandler(content)
    }

    /// Die Zeit ist um: der neutrale Text des Servers geht raus.
    override func serviceExtensionTimeWillExpire() {
        if let handler, let original { handler(original) }
        handler = nil
    }
}
