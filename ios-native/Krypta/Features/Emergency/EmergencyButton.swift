import SwiftUI
import UIKit

/// Der Notfallknopf: auf jedem Bildschirm außer dem Rechner, auch über
/// Blättern, Dialogen und Vollbild-Ansichten.
///
/// Gedrückt halten (0,6 s, ein Ring füllt sich) löscht sofort alles, ohne
/// Rückfrage. Ein kurzes Tippen löscht nichts und zeigt nur den Hinweis —
/// sonst reicht ein Versehen beim Scrollen. Verschieben lässt er sich an
/// jeden Rand, falls er etwas verdeckt.
///
/// Er lebt in einem eigenen Fenster: SwiftUI legt Blätter und Dialoge über
/// alles im App-Fenster, auch über jede Überlagerung dort.
struct EmergencyOverlayInstaller: UIViewRepresentable {
    let model: AppModel

    func makeUIView(context: Context) -> InstallerView { InstallerView(model: model) }
    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        private let model: AppModel

        init(model: AppModel) {
            self.model = model
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let scene = window.windowScene else { return }
            EmergencyOverlay.shared.install(in: scene, appWindow: window, model: model)
        }
    }
}

@MainActor
final class EmergencyOverlay {
    static let shared = EmergencyOverlay()

    private var window: PassthroughWindow?
    private weak var appWindow: UIWindow?
    private var model: AppModel?

    func install(in scene: UIWindowScene, appWindow: UIWindow, model: AppModel) {
        guard window == nil else { return }
        self.appWindow = appWindow
        self.model = model
        let controller = OverlayController()
        controller.appWindow = appWindow
        controller.button.onWipe = { [weak model] in
            Task { await model?.emergencyWipe() }
        }
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.rootViewController = controller
        window.backgroundColor = .clear
        window.isHidden = true
        window.button = controller.button
        self.window = window
        observe()
    }

    /// Sichtbar vor und hinter der Tür, nie beim Rechner — der darf nichts
    /// verraten — und nie im App-Umschalter.
    private var shouldShow: Bool {
        guard let model, !model.privacyCover else { return false }
        switch model.phase {
        case .locked, .vaultPassword, .unlocked: return true
        case .launching, .onboarding, .calculator, .unlocking, .wiping: return false
        }
    }

    private func observe() {
        withObservationTracking {
            _ = shouldShow
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        window?.isHidden = !shouldShow
        if shouldShow { (window?.rootViewController as? OverlayController)?.button.reset() }
    }
}

/// Lässt jede Berührung außerhalb des Knopfs zur App durch.
private final class PassthroughWindow: UIWindow {
    weak var button: EmergencyButton?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let button, !button.isHidden else { return nil }
        let local = convert(point, to: button)
        return button.point(inside: local, with: event) ? button : nil
    }
}

private final class OverlayController: UIViewController {
    let button = EmergencyButton()
    weak var appWindow: UIWindow?
    private var keyboardTop: CGFloat = .greatestFiniteMagnitude

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.addSubview(button.hint)
        view.addSubview(button)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardHidden), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        button.bounds = CGRect(x: 0, y: 0, width: EmergencyButton.size, height: EmergencyButton.size)
        button.keyboardTop = keyboardTop
        button.placeAtRest(in: view, animated: false)
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardTop = frame.minY >= view.bounds.maxY ? .greatestFiniteMagnitude : view.convert(frame, from: nil).minY
        button.keyboardTop = keyboardTop
        button.placeAtRest(in: view, animated: true)
    }

    @objc private func keyboardHidden() {
        keyboardTop = .greatestFiniteMagnitude
        button.keyboardTop = keyboardTop
        button.placeAtRest(in: view, animated: true)
    }

    // Statusleiste und Drehung bestimmt weiter die App.
    private var appController: UIViewController? {
        var top = appWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { appController?.preferredStatusBarStyle ?? .default }
    override var prefersStatusBarHidden: Bool { appController?.prefersStatusBarHidden ?? false }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}

/// Rot, rund, mit Ring, der sich beim Halten füllt.
final class EmergencyButton: UIView {
    static let size: CGFloat = 50
    static let holdDuration: TimeInterval = 0.6
    private static let margin: CGFloat = 10

    var onWipe: (() -> Void)?
    var keyboardTop: CGFloat = .greatestFiniteMagnitude
    let hint = HintBubble()

    private let ring = CAShapeLayer()
    private let icon = UIImageView()
    private var holdTimer: Timer?
    private var touchStart: CGPoint = .zero
    private var centerAtTouch: CGPoint = .zero
    private var isDragging = false
    private var fired = false

    /// Wo der Knopf ruht: an welchem Rand und in welcher Höhe (Anteil).
    private var onLeft: Bool {
        get { UserDefaults.standard.bool(forKey: "emergency.left") }
        set { UserDefaults.standard.set(newValue, forKey: "emergency.left") }
    }
    private var heightFraction: CGFloat {
        get { UserDefaults.standard.object(forKey: "emergency.y") as? CGFloat ?? 0.68 }
        set { UserDefaults.standard.set(newValue, forKey: "emergency.y") }
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        backgroundColor = UIColor.systemRed.withAlphaComponent(0.94)
        layer.cornerRadius = Self.size / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        icon.image = UIImage(systemName: "trash.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        icon.tintColor = .white
        icon.contentMode = .center
        addSubview(icon)

        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 3
        ring.lineCap = .round
        ring.strokeEnd = 0
        layer.addSublayer(ring)

        isAccessibilityElement = true
        accessibilityIdentifier = "emergency.wipe"
        accessibilityLabel = String(localized: "Notfall: alles löschen")
        accessibilityHint = String(localized: "Gedrückt halten, um sofort alles zu löschen.")
        accessibilityTraits = .button
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: "Alles löschen")) { [weak self] _ in
            self?.fire()
            return true
        }]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = bounds
        let inset: CGFloat = 3.5
        ring.frame = bounds
        ring.path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: bounds.width / 2 - inset,
            startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true
        ).cgPath
    }

    /// Größere Trefferfläche als der sichtbare Kreis.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    func reset() {
        cancelHold()
        fired = false
        hint.hide(animated: false)
        transform = .identity
    }

    // MARK: Lage

    func placeAtRest(in container: UIView, animated: Bool) {
        let area = container.bounds.inset(by: container.safeAreaInsets)
        guard area.width > 0, area.height > 0 else { return }
        let half = Self.size / 2
        let x = onLeft ? area.minX + Self.margin + half : area.maxX - Self.margin - half
        var y = area.minY + heightFraction * area.height
        y = min(y, keyboardTop - half - 12)
        y = max(area.minY + half + 60, min(y, area.maxY - half - 8))
        let target = CGPoint(x: x, y: y)
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4) { self.center = target }
        } else {
            center = target
        }
    }

    // MARK: Berührung

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let container = superview else { return }
        touchStart = touch.location(in: container)
        centerAtTouch = center
        isDragging = false
        fired = false
        hint.hide(animated: true)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        UIView.animate(withDuration: 0.15) { self.transform = CGAffineTransform(scaleX: 1.12, y: 1.12) }
        startHold()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let container = superview, !fired else { return }
        let point = touch.location(in: container)
        let dx = point.x - touchStart.x, dy = point.y - touchStart.y
        if !isDragging, hypot(dx, dy) > 10 {
            isDragging = true
            cancelHold()
        }
        if isDragging {
            center = CGPoint(x: centerAtTouch.x + dx, y: centerAtTouch.y + dy)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouch(tapped: !isDragging && !fired)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouch(tapped: false)
    }

    private func finishTouch(tapped: Bool) {
        guard !fired else { return }
        cancelHold()
        UIView.animate(withDuration: 0.2) { self.transform = .identity }
        guard let container = superview else { return }
        if isDragging {
            let area = container.bounds.inset(by: container.safeAreaInsets)
            onLeft = center.x < container.bounds.midX
            if area.height > 0 { heightFraction = max(0, min(1, (center.y - area.minY) / area.height)) }
            placeAtRest(in: container, animated: true)
        } else if tapped {
            hint.show(next: self, in: container, onLeft: onLeft)
        }
        isDragging = false
    }

    private func startHold() {
        ring.removeAllAnimations()
        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = 0
        fill.toValue = 1
        fill.duration = Self.holdDuration
        fill.fillMode = .forwards
        fill.isRemovedOnCompletion = false
        ring.add(fill, forKey: "hold")
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        ring.removeAllAnimations()
        ring.strokeEnd = 0
    }

    private func fire() {
        guard !fired else { return }
        fired = true
        holdTimer?.invalidate()
        holdTimer = nil
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        onWipe?()
    }
}

/// „Gedrückt halten …" neben dem Knopf, nach kurzer Zeit wieder weg.
final class HintBubble: UIView {
    private let label = UILabel()
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.97)
        layer.cornerRadius = 14
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 8
        label.text = String(localized: "Gedrückt halten, um sofort alles zu löschen.")
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .label
        label.numberOfLines = 2
        addSubview(label)
        alpha = 0
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(next button: UIView, in container: UIView, onLeft: Bool) {
        let maxWidth = min(240, container.bounds.width - EmergencyButton.size - 48)
        let size = label.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let width = size.width + 24, height = size.height + 16
        let x = onLeft ? button.frame.maxX + 10 : button.frame.minX - 10 - width
        frame = CGRect(x: x, y: button.center.y - height / 2, width: width, height: height)
        label.frame = bounds.insetBy(dx: 12, dy: 8)
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func hide(animated: Bool) {
        hideWork?.cancel()
        if animated {
            UIView.animate(withDuration: 0.2) { self.alpha = 0 }
        } else {
            alpha = 0
        }
    }
}
