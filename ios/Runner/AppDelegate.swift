import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let securityChannel = "krypta/security"
  private let screenshotEventChannel = "krypta/screenshot_events"
  private var screenshotEventSink: FlutterEventSink?
  private var isSecureFlagEnabled = false

  /// Hidden secure text field used to mask app content in screenshots and
  /// screen recordings. iOS provides NO API to block a screenshot itself,
  /// but content drawn inside a `isSecureTextEntry` field's render layer is
  /// excluded by the OS from screenshots, screen recordings and AirPlay
  /// mirroring. We reparent the window's layer under that protected canvas
  /// once, then just toggle `isSecureTextEntry` to turn masking on/off.
  /// Kill switch for the capture-masking layer trick. Set to `false` to ship a
  /// build that never touches the window's layer tree: screenshots then show
  /// real content again (the warning stays honest about that), but the UI can
  /// physically not end up shifted. Flip this if a device build ever shows the
  /// layout problem from build 68 again.
  private let maskContentInCaptures = true
  private let secureMaskField = SecureMaskField()
  private var secureMaskInstalled = false
  /// The secure-canvas layer that masks captures, and the window layer's
  /// original parent — cached so a toggle can re-verify the reparenting is
  /// still intact and rebuild it if UIKit ever swapped the field's sublayers.
  private var secureCanvasLayer: CALayer?
  private var savedOriginalSuperlayer: CALayer?
  /// The window layer frame in that original parent, captured before the
  /// first reparenting — the reference every geometry check compares against.
  private var savedOriginalWindowFrame: CGRect?
  private var secureMaskWatchdogInstalled = false
  private var isRepairingMask = false

  /// VERIFIED runtime state: true only once the secure canvas was actually
  /// installed AND masking is currently on. Distinct from "Dart requested
  /// protection" — the screenshot warning reports THIS, so a future iOS
  /// release that breaks the private-canvas behavior cannot make the app
  /// claim content was protected when it wasn't.
  private var isScreenshotMaskActive = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register platform channel handler for hardware security queries.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: securityChannel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleMethodCall(call, result: result)
      }

      // Screenshot event detection via EventChannel
      let eventChannel = FlutterEventChannel(
        name: screenshotEventChannel,
        binaryMessenger: controller.binaryMessenger
      )
      eventChannel.setStreamHandler(ScreenshotStreamHandler(delegate: self))
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Method Channel Handler

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enableSecureFlag":
      // Resolve only AFTER masking is actually installed on the main
      // thread, so Dart never renders the messenger before the mask is up.
      setScreenshotMask(true) { active in
        self.isSecureFlagEnabled = active
        result(active)
      }
    case "disableSecureFlag":
      setScreenshotMask(false) { _ in
        self.isSecureFlagEnabled = false
        result(true)
      }
    case "isStrongBoxAvailable":
      // iOS equivalent: Secure Enclave
      result(isSecureEnclaveAvailable())
    case "isHardwareKeyReady":
      result(isHardwareKeyReady())
    case "createHardwareBoundKey":
      let created = createHardwareBoundKey()
      result(created)
    case "wrapKey":
      guard let args = call.arguments as? [String: Any],
            let keyData = args["key"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'key'", details: nil))
        return
      }
      if let wrapped = wrapKey(keyData.data) {
        result(wrapped)
      } else {
        result(FlutterError(code: "WRAP_FAILED", message: "Key wrapping failed", details: nil))
      }
    case "unwrapKey":
      guard let args = call.arguments as? [String: Any],
            let wrappedData = args["wrapped"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'wrapped'", details: nil))
        return
      }
      if let unwrapped = unwrapKey(wrappedData.data) {
        result(unwrapped)
      } else {
        result(FlutterError(code: "UNWRAP_FAILED", message: "Key unwrapping failed", details: nil))
      }
    case "deleteHardwareBoundKey":
      deleteHardwareBoundKey()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Secure Enclave Operations

  /// Check if the device has a Secure Enclave (A7+ chip, iPhone 5s+).
  /// All modern iOS devices (2013+) have it.
  private func isSecureEnclaveAvailable() -> Bool {
    // Try to access Secure Enclave by checking if we can create an EC key there.
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeEC,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
    ]
    var error: Unmanaged<CFError>?
    let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
    // Balance the +1 retain the Security framework hands us. Deliberately not
    // logged: a "Krypta"/"Secure Enclave" line in the device log would give
    // away what the calculator really is.
    error?.release()
    if key != nil {
      // Key created successfully — Secure Enclave is available.
      // We don't store it; this is just a probe.
      return true
    }
    return false
  }

  private let hardwareKeyTag = "com.krypta.hw.wrapping".data(using: .utf8)!

  /// Check if a hardware-bound wrapping key already exists in Keychain.
  private func isHardwareKeyReady() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: hardwareKeyTag,
      kSecReturnRef as String: false,
    ]
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
  }

  /// Create a Secure Enclave-backed EC P-256 key for key wrapping.
  ///
  /// Unlike Android's AES in StrongBox, iOS Secure Enclave only supports
  /// ECDH/ECDSA on P-256. For wrapping, we use ECIES:
  /// encrypt with the SE public key, decrypt with the SE private key.
  private func createHardwareBoundKey() -> Bool {
    if isHardwareKeyReady() { return true }

    // Returns nil on devices/configurations that reject the flag combination.
    // This runs off a Flutter method channel, so a force unwrap here would
    // crash the app instead of falling back to software key wrapping, which
    // the Bool return value already models.
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      .privateKeyUsage,
      nil
    ) else {
      return false
    }

    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeEC,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: hardwareKeyTag,
        kSecAttrAccessControl as String: access,
      ] as [String: Any],
    ]

    var error: Unmanaged<CFError>?
    let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
    error?.release()
    return privateKey != nil
  }

  /// Wrap a key using ECIES with the Secure Enclave public key.
  private func wrapKey(_ plainKey: Data) -> FlutterStandardTypedData? {
    guard let privateKey = loadHardwareKey(),
          let publicKey = SecKeyCopyPublicKey(privateKey) else {
      return nil
    }

    var error: Unmanaged<CFError>?
    let encryptedData = SecKeyCreateEncryptedData(
      publicKey,
      .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
      plainKey as CFData,
      &error
    )
    error?.release()
    guard let encrypted = encryptedData else {
      return nil
    }

    return FlutterStandardTypedData(bytes: encrypted as Data)
  }

  /// Unwrap a key using ECIES with the Secure Enclave private key.
  private func unwrapKey(_ wrapped: Data) -> FlutterStandardTypedData? {
    guard let privateKey = loadHardwareKey() else { return nil }

    var error: Unmanaged<CFError>?
    let decryptedData = SecKeyCreateDecryptedData(
      privateKey,
      .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
      wrapped as CFData,
      &error
    )
    error?.release()
    guard let decrypted = decryptedData else {
      return nil
    }

    return FlutterStandardTypedData(bytes: decrypted as Data)
  }

  /// Delete the hardware-bound key from Keychain.
  private func deleteHardwareBoundKey() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: hardwareKeyTag,
    ]
    SecItemDelete(query as CFDictionary)
  }

  /// Load the Secure Enclave private key reference.
  private func loadHardwareKey() -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: hardwareKeyTag,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else { return nil }
    // B1: nil-safe cast. `errSecSuccess` does not guarantee `item` is
    // non-nil on every iOS release, and the previous `as!` would crash
    // the app in that rare path. Returning nil lets the caller fall back.
    guard let key = item, CFGetTypeID(key) == SecKeyGetTypeID() else {
      return nil
    }
    return (key as! SecKey)
  }

  // MARK: - Screenshot & Screen Recording Content Masking

  /// Install the secure-canvas mask once (lazily, when protection is first
  /// requested and the window exists), then drive it via `isSecureTextEntry`.
  ///
  /// The reparenting only affects what the OS *captures* — the content keeps
  /// rendering normally on the physical display. Returns whether the mask is
  /// installed and verified — structurally AND geometrically. If a future iOS
  /// release ever stops honoring this, install fails CLOSED here (we report
  /// no protection) and the post-hoc screenshot detection still warns the
  /// user honestly.
  @discardableResult
  private func installSecureMaskIfNeeded() -> Bool {
    guard maskContentInCaptures else { return false }
    if secureMaskInstalled { return true }
    guard let window = window else { return false }
    // Reuse the cached original parent on reinstall so we never treat a
    // broken secure canvas as the "original" superlayer.
    guard let originalSuperlayer = savedOriginalSuperlayer ?? window.layer.superlayer
    else { return false }
    savedOriginalSuperlayer = originalSuperlayer
    // Never start an install from a half-broken tree: if the window layer is
    // currently parented anywhere but its original home, put it back first.
    // Otherwise an early return below (no candidates, canvas gone) would leave
    // it stranded under a detached canvas — a black screen.
    if window.layer.superlayer !== originalSuperlayer {
      originalSuperlayer.addSublayer(window.layer)
      window.layer.frame = CGRect(origin: savedOriginalWindowFrame?.origin ?? .zero,
                                  size: window.bounds.size)
      secureCanvasLayer = nil
    }
    // Where the window sits in its original parent. Captured before the very
    // first move only: afterwards window.layer.frame is expressed in canvas
    // coordinates and would poison the reference.
    if savedOriginalWindowFrame == nil { savedOriginalWindowFrame = window.layer.frame }

    secureMaskField.isUserInteractionEnabled = false
    if secureMaskField.superview == nil {
      secureMaskField.translatesAutoresizingMaskIntoConstraints = false
      window.addSubview(secureMaskField)
      // Pin to the window's TOP-LEFT at full size — never centered. Every
      // descendant inherits this layer's origin, so a centered field offsets
      // the whole UI by half a screen down and right; that is exactly what
      // shipped in build 68. Full-size + Auto Layout also keeps the origin at
      // zero across rotation and iPad Split View resizes.
      NSLayoutConstraint.activate([
        secureMaskField.topAnchor.constraint(equalTo: window.topAnchor),
        secureMaskField.leadingAnchor.constraint(equalTo: window.leadingAnchor),
        secureMaskField.widthAnchor.constraint(equalTo: window.widthAnchor),
        secureMaskField.heightAnchor.constraint(equalTo: window.heightAnchor),
      ])
    }

    // The secure render canvas only exists once isSecureTextEntry is on, so
    // force it on and lay out BEFORE looking the canvas layer up.
    secureMaskField.isSecureTextEntry = true
    window.layoutIfNeeded()
    secureMaskField.layoutIfNeeded()

    // Take ONLY the sublayer the running OS is known to use for the secure
    // canvas: iOS 17+ the first, earlier releases the last. Deliberately no
    // fallback to the other one — none of our checks can tell a secure canvas
    // from an ordinary layer (they verify ancestry, placement and visibility,
    // all of which an arbitrary layer satisfies), so accepting the alternate
    // would mean claiming a protection we cannot establish. If the expected
    // layer does not verify we fail closed: UI correct, masking off, and the
    // screenshot warning says so.
    let sublayers = secureMaskField.layer.sublayers ?? []
    let canvasCandidate: CALayer? = {
      if #available(iOS 17.0, *) { return sublayers.first }
      return sublayers.last
    }()
    guard let canvas = canvasCandidate else { return false } // no canvas — fail closed

    // Reparent: put the field's layer where the window layer was, then nest
    // the window layer inside the secure canvas. addSublayer detaches the
    // window layer from any previous (possibly stale) parent automatically.
    originalSuperlayer.addSublayer(secureMaskField.layer)

    canvas.addSublayer(window.layer)
    secureCanvasLayer = canvas
    applySecureMaskGeometry()
    if isSecureMaskStructureIntact() && isWindowGeometryIntact()
        && isAncestorChainRenderable() {
      secureMaskInstalled = true
      startSecureMaskWatchdog()
      scheduleSecureMaskRecheck()
      return true
    }

    // Not verified — restore the original tree. A correctly positioned UI
    // without masking always beats a shifted or blank one that claims a
    // protection it does not actually have.
    restoreOriginalParenting()
    return false
  }

  /// Re-assert the window layer's geometry inside the secure canvas.
  ///
  /// A layer inherits its ancestors' coordinate system, and UIKit re-assigns
  /// `window.layer.frame` in ORIGINAL parent coordinates on every scene
  /// resize (rotation, iPad Split View, keyboard). Both effects have to be
  /// compensated or the UI drifts off-screen.
  private func applySecureMaskGeometry() {
    guard let window = window,
          let canvas = secureCanvasLayer,
          let originalSuperlayer = savedOriginalSuperlayer,
          let reference = savedOriginalWindowFrame else { return }
    // window.bounds is parent-independent and always current, so it stays
    // correct across rotation; the origin remains the one the window had
    // before the move.
    let target = CGRect(origin: reference.origin, size: window.bounds.size)
    let originInCanvas = originalSuperlayer.convert(target.origin, to: canvas)
    window.layer.frame = CGRect(origin: originInCanvas, size: target.size)
  }

  /// True iff the window still renders exactly where it would without the
  /// mask. This is the check that was missing in build 68: the structure was
  /// verified, the geometry was not — so a half-screen offset shipped while
  /// the app reported "protected".
  private func isWindowGeometryIntact() -> Bool {
    guard let window = window,
          let originalSuperlayer = savedOriginalSuperlayer,
          let reference = savedOriginalWindowFrame,
          window.layer.superlayer != nil else { return false }
    let tolerance: CGFloat = 0.5
    // Convert the whole rect, not just the origin: this walks every ancestor
    // and therefore also catches a scale, rotation or translation applied by
    // any layer between the window and its original parent.
    let rendered = originalSuperlayer.convert(window.layer.bounds, from: window.layer)
    let expected = CGRect(origin: reference.origin, size: window.bounds.size)
    return abs(rendered.origin.x - expected.origin.x) <= tolerance
        && abs(rendered.origin.y - expected.origin.y) <= tolerance
        && abs(rendered.width - expected.width) <= tolerance
        && abs(rendered.height - expected.height) <= tolerance
  }

  /// True iff no layer between the window and its original parent can hide or
  /// clip the UI. Geometry alone is not enough: a wrong candidate layer can map
  /// the window rect correctly and still be hidden, transparent or masked.
  private func isAncestorChainRenderable() -> Bool {
    guard let window = window, let original = savedOriginalSuperlayer else { return false }
    var node: CALayer? = window.layer.superlayer
    while let layer = node, layer !== original {
      if layer.isHidden || layer.opacity < 0.99 { return false }
      if layer.masksToBounds {
        let windowRect = layer.convert(window.layer.bounds, from: window.layer)
        // Half-point slack: sub-pixel rounding must not reject a canvas that
        // does contain the window, which would needlessly drop the masking.
        if !layer.bounds.insetBy(dx: -0.5, dy: -0.5).contains(windowRect) { return false }
      }
      node = layer.superlayer
    }
    // The chain must actually reach the original parent, not dead-end.
    return node === original
  }

  /// True iff the reparenting is still structurally intact: the window layer
  /// sits under the secure canvas, which sits under the field's layer, which
  /// sits under the window's original parent. UIKit can rebuild a secure
  /// field's sublayers across toggles, so we re-check.
  private func isSecureMaskStructureIntact() -> Bool {
    guard let canvas = secureCanvasLayer, let window = window else { return false }
    return window.layer.superlayer === canvas
        && canvas.superlayer === secureMaskField.layer
        && secureMaskField.layer.superlayer === savedOriginalSuperlayer
  }

  /// Tear the mask down and put the window layer back where it belongs.
  /// Runs whenever verification fails: fail VISIBLE, never leave the user
  /// with a shifted, clipped or black screen.
  private func restoreOriginalParenting() {
    secureMaskField.isSecureTextEntry = false
    if let window = window, let originalSuperlayer = savedOriginalSuperlayer {
      originalSuperlayer.addSublayer(window.layer)
      window.layer.frame = CGRect(origin: savedOriginalWindowFrame?.origin ?? .zero,
                                  size: window.bounds.size)
    }
    // Drop the field out of the view hierarchy too, so UIKit is left with a
    // consistent view/layer tree; a later re-install rebuilds it cleanly.
    secureMaskField.layer.removeFromSuperlayer()
    secureMaskField.removeFromSuperview()
    secureCanvasLayer = nil
    secureMaskInstalled = false
    isScreenshotMaskActive = false
  }

  /// Watch the layout events that can move or orphan the window layer:
  /// rotation, scene resizes (iPad Split View) and every foreground return.
  /// Repair if possible, tear the mask down otherwise.
  private func startSecureMaskWatchdog() {
    guard !secureMaskWatchdogInstalled else { return }
    secureMaskWatchdogInstalled = true
    // The field is pinned to the window, so UIKit lays it out on EVERY window
    // resize: rotation, iPad Split View, Stage Manager, safe-area changes.
    // That is the general scene-resize signal an orientation notification is
    // not — dragging a Split View divider never changes device orientation.
    secureMaskField.onLayout = { [weak self] in self?.scheduleSecureMaskRepair() }
    // Foreground returns are covered by applicationDidBecomeActive below.
  }

  /// Coalesce repairs: the layout hook fires inside a layout pass and the
  /// repair mutates layer frames, so run it on the next runloop turn and never
  /// re-enter while one is already queued.
  private func scheduleSecureMaskRepair() {
    guard !isRepairingMask else { return }
    isRepairingMask = true
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.isRepairingMask = false
      self.repairSecureMaskOrRestore()
    }
  }

  /// Verification right after the install only proves the tree was correct at
  /// that instant. UIKit runs further layout passes afterwards (safe-area,
  /// keyboard, Flutter's own view setup), so re-check once the runloop has
  /// settled and once again shortly after — and drop the mask if the UI moved.
  private func scheduleSecureMaskRecheck() {
    scheduleSecureMaskRepair()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
      self?.repairSecureMaskOrRestore()
    }
  }

  private func repairSecureMaskOrRestore() {
    guard secureMaskInstalled else { return }
    if !isSecureMaskStructureIntact() {
      restoreOriginalParenting()
      return
    }
    applySecureMaskGeometry()
    if !isWindowGeometryIntact() || !isAncestorChainRenderable() {
      restoreOriginalParenting()
    }
  }

  /// Toggle masking on/off, resolving [completion] on the main thread with
  /// the VERIFIED active state (true = canvas installed, intact, masking on).
  private func setScreenshotMask(_ on: Bool, completion: @escaping (Bool) -> Void) {
    let work = {
      // Nothing to tear down if we never installed — don't build the private
      // layer structure just to immediately disable it.
      if !on && !self.secureMaskInstalled {
        self.isScreenshotMaskActive = false
        completion(false)
        return
      }

      var ok = self.installSecureMaskIfNeeded()
      // If UIKit tore a prior install down, restore FIRST and rebuild from a
      // visible state — a reinstall that bails early must never leave the
      // window layer hanging under a detached canvas.
      if ok && !self.isSecureMaskStructureIntact() {
        self.restoreOriginalParenting()
        ok = self.installSecureMaskIfNeeded()
      }
      if ok {
        self.secureMaskField.isSecureTextEntry = on
        // A toggle can rebuild sublayers and reset frames — re-assert the
        // geometry and confirm BOTH invariants survived.
        self.applySecureMaskGeometry()
        ok = self.isSecureMaskStructureIntact() && self.isWindowGeometryIntact()
          && self.isAncestorChainRenderable()
        if !ok { self.restoreOriginalParenting() }
      }

      self.isScreenshotMaskActive = on && ok
      completion(self.isScreenshotMaskActive)
    }
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  // MARK: - App-switcher snapshot masking

  /// Tag of the opaque cover used for app-switcher snapshots.
  private static let snapshotMaskTag = 9999

  /// Take every snapshot mask off the window.
  ///
  /// `viewWithTag` returns only the first match, so removing one view per
  /// resume is not enough: iOS can deliver `willResignActive` more than once
  /// before the next `didBecomeActive` (Siri over the app, a call banner, a
  /// notification-centre pull followed by the switcher). Each of those added
  /// another cover, one resume removed one, and the leftovers stayed on top —
  /// a permanently black app with no way back. Idempotent by construction.
  private func removeSnapshotMasks() {
    guard let window = window else { return }
    for view in window.subviews where view.tag == AppDelegate.snapshotMaskTag {
      view.removeFromSuperview()
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // Keep the black mask one runloop tick longer than strictly needed,
    // so Flutter has time to render the Calculator frame after our
    // background-lock logic in app.dart resets the route. This avoids a
    // flash of the previous (now stale) screen content during resume.
    DispatchQueue.main.async {
      self.removeSnapshotMasks()
      // A backgrounded app can come back with a rebuilt layer tree or a
      // resized scene — re-assert the mask geometry, or drop the mask if it
      // cannot be repaired, so the UI is never left shifted.
      self.repairSecureMaskOrRestore()
    }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    // Cover the screen with an opaque black view so the iOS app-switcher
    // snapshot and any transient inactive-state frames render as solid
    // black instead of leaking the messenger UI or showing a white flash.
    guard let window = window else { return }
    // Clear any cover left over from an unbalanced resign/become pair before
    // adding this one, so at most one is ever on the window.
    removeSnapshotMasks()
    let blackView = UIView(frame: window.bounds)
    blackView.backgroundColor = .black
    blackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blackView.tag = AppDelegate.snapshotMaskTag
    window.addSubview(blackView)
  }

  // MARK: - Screenshot Event Detection

  func startScreenshotDetection() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
  }

  func stopScreenshotDetection() {
    NotificationCenter.default.removeObserver(
      self,
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
  }

  @objc private func screenshotTaken() {
    // iOS cannot block the screenshot itself; it fires this notification
    // only AFTER the capture. Report the VERIFIED mask state, not what Dart
    // requested:
    //   true  -> mask installed & on, so the captured image is blank/masked
    //   false -> no active mask, the screenshot shows real content
    // The Dart layer turns this into an honest, non-misleading warning.
    screenshotEventSink?(isScreenshotMaskActive)
  }
}

// MARK: - Screenshot EventChannel Stream Handler

class ScreenshotStreamHandler: NSObject, FlutterStreamHandler {
  weak var delegate: AppDelegate?

  init(delegate: AppDelegate) {
    self.delegate = delegate
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    delegate?.screenshotEventSink = events
    delegate?.startScreenshotDetection()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    delegate?.screenshotEventSink = nil
    delegate?.stopScreenshotDetection()
    return nil
  }
}

/// Secure-canvas host. Subclassed purely for `layoutSubviews`: pinned to the
/// window, that callback is the most reliable public signal that the scene
/// geometry changed — including iPad Split View and Stage Manager resizes,
/// which post no orientation notification.
class SecureMaskField: UITextField {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}
