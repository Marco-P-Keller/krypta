import CloudKit
import Foundation

/// Was in einer Mitteilung von CloudKit steckt (App und Extension).
///
/// Das Abo (`CloudKitRelay.subscribeToInbox`) verlangt vom neuen Eintrag nur
/// das Feld `tag`, den Anhänger aus NotificationTag. CloudKit legt es unter
/// `ck.qry.af` in die Mitteilung.
enum PushPayload {
    /// Der feste Text, den CloudKit schickt — ein Schlüssel in
    /// Localizable.xcstrings der App, damit er auch dann übersetzt ist, wenn
    /// die Extension nicht rechtzeitig fertig wird.
    static let coverKey = "Du hast eine neue Nachricht erhalten"

    static func tag(from userInfo: [AnyHashable: Any]) -> String? {
        if let ck = userInfo["ck"] as? [String: Any],
           let query = ck["qry"] as? [String: Any],
           let fields = query["af"] as? [String: Any],
           let tag = fields["tag"] as? String {
            return tag
        }
        // Falls Apple den Aufbau einmal ändert: CloudKit liest ihn selbst.
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification
        return notification?.recordFields?["tag"] as? String
    }
}
