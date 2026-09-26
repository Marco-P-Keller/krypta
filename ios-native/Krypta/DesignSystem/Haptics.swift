import UIKit

/// Schlichtes Haptik-Feedback an den Stellen, die zählen — kurz und leise,
/// nie bei jedem Tippen. iOS schaltet es mit „Systemhaptik" (Einstellungen →
/// Töne & Haptik) selbst ab.
///
/// Für Zustände, die sich in einer Ansicht ändern, lieber `.sensoryFeedback`;
/// das hier ist für Knöpfe und Abläufe, die in einer Aktion enden.
@MainActor
enum Haptics {
    /// Etwas ist unterwegs oder übernommen: Senden, Kopieren.
    static func confirm() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5) }
    /// Es hat geklappt: Kontakt hinzugefügt, Anfrage angenommen, bestätigt.
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// Etwas verschwindet: löschen, leeren, blockieren, ablehnen.
    static func destructive() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.55) }
    /// Ging nicht: falsches Passwort, Kontakt nicht gefunden.
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    /// Eine Einstellung wechselt.
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
