import SwiftUI
import UIKit

/// Hält Inhalte aus Bildschirmfotos, Aufnahmen und Spiegelungen heraus.
///
/// iOS hat dafür keine öffentliche Schnittstelle. Es gibt aber eine Fläche,
/// die das System selbst aus jeder Aufnahme herausnimmt: die Zeichenfläche
/// eines Passwortfelds (`isSecureTextEntry`). Diese Fläche wird hier aus dem
/// Feld gelöst und als Behälter für den Chat verwendet. Auf dem Display
/// erscheint alles normal, im Bildschirmfoto bleibt die Stelle leer.
///
/// Das ist kein dokumentiertes Verhalten. Deshalb prüft `isEffective`, ob die
/// Fläche wirklich gefunden wurde; fehlt sie, zeigt die App den Inhalt
/// ungeschützt und sagt das in den Einstellungen, statt einen Schutz zu
/// behaupten. Die Meldung an die Gegenseite läuft in jedem Fall.
struct ScreenshotShield<Content: View>: UIViewControllerRepresentable {
    var isEnabled: Bool
    let content: Content

    init(isEnabled: Bool = true, @ViewBuilder content: () -> Content) {
        self.isEnabled = isEnabled
        self.content = content()
    }

    func makeUIViewController(context: Context) -> ShieldController<Content> {
        ShieldController(rootView: content, isEnabled: isEnabled)
    }

    func updateUIViewController(_ controller: ShieldController<Content>, context: Context) {
        controller.hosting.rootView = content
        controller.setEnabled(isEnabled)
    }
}

final class ShieldController<Content: View>: UIViewController {
    let hosting: UIHostingController<Content>
    private let field = UITextField()
    private var canvas: UIView?
    private var enabled: Bool

    init(rootView: Content, isEnabled: Bool) {
        hosting = UIHostingController(rootView: rootView)
        enabled = isEnabled
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        attach()
        hosting.didMove(toParent: self)
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        field.isSecureTextEntry = on
    }

    /// Die geschützte Fläche des Felds als Behälter einsetzen. Ohne sie
    /// kommt der Inhalt direkt in die eigene Ansicht.
    private func attach() {
        field.isSecureTextEntry = true
        if let surface = ScreenshotProtection.secureSurface(of: field) {
            canvas = surface
            // Liegt unter der geschützten Fläche: auf dem Display verdeckt,
            // im Bildschirmfoto das Einzige, was bleibt.
            let placeholder = UIHostingController(rootView: ShieldPlaceholder()).view!
            view.addSubview(placeholder)
            pin(placeholder, to: view)
            surface.subviews.forEach { $0.removeFromSuperview() }
            surface.isUserInteractionEnabled = true
            surface.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(surface)
            pin(surface, to: view)
            surface.addSubview(hosting.view)
            pin(hosting.view, to: surface)
            ScreenshotProtection.isEffective = true
        } else {
            view.addSubview(hosting.view)
            pin(hosting.view, to: view)
            ScreenshotProtection.isEffective = false
        }
        field.isSecureTextEntry = enabled
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}

enum ScreenshotProtection {
    /// Ob die geschützte Fläche auf diesem System gefunden wurde.
    @MainActor static var isEffective = false

    /// Die Zeichenfläche eines Passwortfelds. Ihr Klassenname hat sich über
    /// die iOS-Versionen geändert; gesucht wird deshalb nach dem Teil, der
    /// gleich geblieben ist.
    @MainActor static func secureSurface(of field: UITextField) -> UIView? {
        field.subviews.first { String(describing: type(of: $0)).contains("CanvasView") }
            ?? field.subviews.first { String(describing: type(of: $0)).contains("LayoutCanvas") }
    }
}

/// Was ein Bildschirmfoto statt des Chats zeigt.
private struct ShieldPlaceholder: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 34, weight: .medium))
                Text("Inhalt geschützt")
                    .font(.headline)
            }
            .foregroundStyle(.secondary)
        }
    }
}
