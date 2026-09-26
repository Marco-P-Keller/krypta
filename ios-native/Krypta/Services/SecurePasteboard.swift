import UIKit
import UniformTypeIdentifiers

/// Kopieren ohne Spuren: nur auf diesem Gerät — nicht über die universelle
/// Zwischenablage auf Mac oder iPad — und nach kurzer Zeit wieder weg.
enum SecurePasteboard {
    /// Nachrichtentext: eine Minute reicht zum Einfügen.
    static let messageLifetime: TimeInterval = 60
    /// Die eigene Kennung wird oft erst in einer anderen App eingefügt.
    static let idLifetime: TimeInterval = 5 * 60

    static func copy(_ text: String, lifetime: TimeInterval = messageLifetime) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(lifetime)]
        )
    }
}
