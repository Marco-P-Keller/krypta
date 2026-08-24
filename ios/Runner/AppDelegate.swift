import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let securityChannel = "krypta/security"
  private let screenshotEventChannel = "krypta/screenshot_events"
  private let captureEventChannel = "krypta/capture_events"
  // `fileprivate`, nicht `private`: ScreenshotStreamHandler ist eine eigene
  // Klasse weiter unten in dieser Datei und setzt den Sink. `private` gilt
  // fuer den Typ (plus dessen Extensions), nicht fuer die Datei — ein
  // fremder Typ kaeme auch aus derselben Datei nicht heran.
  fileprivate var screenshotEventSink: FlutterEventSink?
  fileprivate var captureEventSink: FlutterEventSink?
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

  /// Warum der letzte Installationsversuch endete. Rein fuer die Diagnose:
  /// ohne Mac und ohne Xcode-Konsole ist das der einzige Weg, vom Geraet zu
  /// erfahren, WELCHE der Pruefungen auf iOS 26 fehlschlaegt, statt es zu
  /// raten. Werte: ok, killswitch, noWindow, noSuperlayer, noCandidate,
  /// structure, geometry, renderable.
  private var lastMaskFailureReason = "nie versucht"
  /// Index des Sublayers, den der letzte Versuch als Zeichenflaeche genommen
  /// hat (-1 = keiner).
  private var lastCandidateIndex = -1

  // Aufnahme-/Spiegelungsschutz (UIScreen.isCaptured) — siehe eigener
  // Abschnitt weiter unten.
  private static let captureMaskTag = 9998
  private var captureObserverInstalled = false
  /// Der Hinweis, den die Abdeckung traegt. Kommt lokalisiert aus Dart, damit
  /// die Uebersetzung in den .arb-Dateien bleibt und hier keine zweite,
  /// nachzupflegende Textquelle entsteht.
  private var captureNoticeText = ""

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

      // Zweiter Strom: Bildschirmaufnahme / Spiegelung an oder aus.
      let captureChannel = FlutterEventChannel(
        name: captureEventChannel,
        binaryMessenger: controller.binaryMessenger
      )
      captureChannel.setStreamHandler(CaptureStreamHandler(delegate: self))
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Method Channel Handler

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enableSecureFlag":
      // Der Hinweistext fuer die Aufnahme-Abdeckung kommt lokalisiert von
      // Dart mit. Fehlt er, bleibt die Abdeckung stumm schwarz.
      if let args = call.arguments as? [String: Any],
         let notice = args["captureNotice"] as? String {
        captureNoticeText = notice
      }
      // Aufnahme-/Spiegelungsschutz haengt NICHT am Layer-Trick: er greift
      // auch dann, wenn die Maske unten fehlschlaegt.
      startCaptureMonitoring()
      // Resolve only AFTER masking is actually installed on the main
      // thread, so Dart never renders the messenger before the mask is up.
      setScreenshotMask(true) { active in
        self.isSecureFlagEnabled = active
        result(active)
      }
    case "disableSecureFlag":
      stopCaptureMonitoring()
      setScreenshotMask(false) { _ in
        self.isSecureFlagEnabled = false
        result(true)
      }
    case "isScreenshotProtectionActive":
      // Der GEPRUEFTE Zustand, direkt aus der Laufzeit. Dart hielt das bisher
      // nur als Kopie vom letzten enable-Aufruf; der Watchdog kann die Maske
      // danach abbauen, ohne dass Dart davon je erfaehrt. Genau diese
      // veraltete Kopie liess den Einstellungs-Schalter "an" zeigen, waehrend
      // nichts geschuetzt war.
      result(isScreenshotMaskActive)
    case "isScreenCaptured":
      result(isScreenBeingCaptured)
    case "diagnoseScreenshotMask":
      diagnoseSecureMask { report in result(report) }
    case "forceSecureMaskCandidate":
      guard let args = call.arguments as? [String: Any],
            let index = args["index"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'index'", details: nil))
        return
      }
      forceSecureMaskCandidate(index) { ok in result(ok) }
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
  ///
  /// [forcedCandidateIndex] ist ausschliesslich fuer die Geraete-Diagnose da:
  /// damit laesst sich vom Geraet aus jeder Sublayer einzeln als
  /// Zeichenflaeche durchprobieren. Der normale Pfad (nil) waehlt weiter
  /// genau wie bisher — bevor nicht vom Geraet feststeht, welcher Index auf
  /// iOS 26 stimmt, wird hier nichts geraten.
  @discardableResult
  private func installSecureMaskIfNeeded(forcedCandidateIndex: Int? = nil) -> Bool {
    guard maskContentInCaptures else {
      lastMaskFailureReason = "killswitch"
      return false
    }
    if secureMaskInstalled && forcedCandidateIndex == nil { return true }
    guard let window = window else {
      lastMaskFailureReason = "noWindow"
      return false
    }
    // Reuse the cached original parent on reinstall so we never treat a
    // broken secure canvas as the "original" superlayer.
    guard let originalSuperlayer = savedOriginalSuperlayer ?? window.layer.superlayer
    else {
      lastMaskFailureReason = "noSuperlayer"
      return false
    }
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

    prepareSecureField(in: window)

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
      // Diagnosepfad, siehe Doku oben: einen bestimmten Sublayer erzwingen.
      if let forced = forcedCandidateIndex {
        return sublayers.indices.contains(forced) ? sublayers[forced] : nil
      }
      if #available(iOS 17.0, *) { return sublayers.first }
      return sublayers.last
    }()
    lastCandidateIndex = canvasCandidate
      .flatMap { c in sublayers.firstIndex(where: { $0 === c }) } ?? -1
    guard let canvas = canvasCandidate else {
      lastMaskFailureReason = "noCandidate"
      return false // no canvas — fail closed
    }

    // Reparent: put the field's layer where the window layer was, then nest
    // the window layer inside the secure canvas. addSublayer detaches the
    // window layer from any previous (possibly stale) parent automatically.
    originalSuperlayer.addSublayer(secureMaskField.layer)

    canvas.addSublayer(window.layer)
    secureCanvasLayer = canvas
    applySecureMaskGeometry()
    // Einzeln auswerten statt in einem &&-Ausdruck: die Diagnose muss vom
    // Geraet melden koennen, WELCHE Pruefung durchfaellt. Die Kurzschluss-
    // Reihenfolge bleibt dieselbe wie vorher.
    let structureOK = isSecureMaskStructureIntact()
    let geometryOK = structureOK && isWindowGeometryIntact()
    let renderableOK = geometryOK && isAncestorChainRenderable()
    if renderableOK {
      lastMaskFailureReason = "ok"
      secureMaskInstalled = true
      startSecureMaskWatchdog()
      scheduleSecureMaskRecheck()
      return true
    }
    lastMaskFailureReason = !structureOK ? "structure"
      : (!geometryOK ? "geometry" : "renderable")

    // Not verified — restore the original tree. A correctly positioned UI
    // without masking always beats a shifted or blank one that claims a
    // protection it does not actually have.
    restoreOriginalParenting()
    return false
  }

  /// Put the field into the hierarchy and let UIKit build the secure render
  /// canvas — without touching the window's layer tree yet.
  ///
  /// Eigene Funktion, weil die Diagnose sie ebenfalls braucht: ein
  /// fehlgeschlagener Einbau raeumt das Feld wieder ab, und die Sublayer waeren
  /// dann verschwunden, bevor irgendjemand sie ansehen konnte.
  private func prepareSecureField(in window: UIWindow) {
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
    runOnMain(work)
  }

  /// Layer- und View-Baum duerfen nur auf dem Hauptthread angefasst werden.
  private func runOnMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  // MARK: - Geraete-Diagnose fuer die Zeichenflaeche

  /// Einen bestimmten Sublayer als Zeichenflaeche erzwingen und melden, ob die
  /// Pruefungen ihn annehmen.
  ///
  /// Der Sinn: ob iOS 26 die Maske ueberhaupt noch aus Aufnahmen ausschliesst,
  /// laesst sich nur am Geraet feststellen — einen Kandidaten setzen, einen
  /// Screenshot machen, nachsehen ob er schwarz ist. Ohne das braeuchte jeder
  /// Rateversuch einen eigenen Build von rund 45 Minuten.
  private func forceSecureMaskCandidate(_ index: Int, completion: @escaping (Bool) -> Void) {
    runOnMain {
      self.restoreOriginalParenting()
      let ok = self.installSecureMaskIfNeeded(forcedCandidateIndex: index)
      if ok { self.secureMaskField.isSecureTextEntry = true }
      self.isScreenshotMaskActive = ok
      completion(ok)
    }
  }

  /// Die echte Struktur des Secure-Feldes melden, statt sie zu raten.
  ///
  /// Zusaetzlich zur reinen Auflistung wird JEDER Sublayer einmal wirklich
  /// eingebaut und durch dieselben drei Pruefungen geschickt wie im
  /// Normalbetrieb. Danach wird der Ausgangszustand wiederhergestellt.
  private func diagnoseSecureMask(completion: @escaping ([String: Any]) -> Void) {
    runOnMain {
      var report: [String: Any] = [
        "iosVersion": UIDevice.current.systemVersion,
        "killSwitch": self.maskContentInCaptures,
        "isCaptured": self.isScreenBeingCaptured,
        "maskInstalled": self.secureMaskInstalled,
        "maskActive": self.isScreenshotMaskActive,
        "defaultReason": self.lastMaskFailureReason,
        "defaultIndex": self.lastCandidateIndex,
      ]

      let wasActive = self.isScreenshotMaskActive

      // Nur einhaengen und die Zeichenflaeche erzeugen lassen, NICHT
      // einbauen: ein fehlgeschlagener Einbau raeumt das Feld wieder ab, und
      // genau dann — im iOS-26-Fall, um den es hier geht — waere die Liste
      // leer gewesen.
      if let window = self.window { self.prepareSecureField(in: window) }
      let layers = self.secureMaskField.layer.sublayers ?? []
      report["sublayerCount"] = layers.count
      report["subviews"] = self.secureMaskField.subviews.map {
        String(describing: type(of: $0))
      }

      // Erst alle Merkmale einsammeln: die Sonde unten baut den Baum um, und
      // UIKit ersetzt die Sublayer dabei durch neue Objekte.
      var candidates: [[String: Any]] = []
      for i in layers.indices {
        let layer = layers[i]
        candidates.append([
          "index": i,
          "class": String(describing: type(of: layer)),
          "frame": "\(layer.frame)",
          "hidden": layer.isHidden,
          "opacity": Double(layer.opacity),
          "sublayers": layer.sublayers?.count ?? 0,
        ])
      }
      for i in candidates.indices {
        self.restoreOriginalParenting()
        let ok = self.installSecureMaskIfNeeded(forcedCandidateIndex: i)
        candidates[i]["verifies"] = ok
        candidates[i]["reason"] = self.lastMaskFailureReason
      }
      report["candidates"] = candidates

      // Ausgangszustand zurueck — eine Diagnose darf die App nicht in einem
      // halb umgebauten Layer-Baum stehen lassen.
      self.restoreOriginalParenting()
      if wasActive {
        self.setScreenshotMask(true) { active in
          report["restoredActive"] = active
          completion(report)
        }
      } else {
        self.isScreenshotMaskActive = false
        report["restoredActive"] = false
        completion(report)
      }
    }
  }

  // MARK: - Bildschirmaufnahme und Spiegelung (UIScreen.isCaptured)

  /// Der dokumentierte, von Apple unterstuetzte Weg, Aufnahme und Spiegelung
  /// zu erkennen — im Gegensatz zum Layer-Trick oben, der auf undokumentiertem
  /// Verhalten von `isSecureTextEntry` beruht und auf iOS 26.6 nicht mehr
  /// greift. Bis hierher gab es dafuer ueberhaupt keinen Schutz.
  ///
  /// Screenshots bleiben davon unberuehrt: die meldet iOS grundsaetzlich erst
  /// NACH der Aufnahme, verhindern kann man sie nicht.
  private var isScreenBeingCaptured: Bool {
    if let screen = window?.windowScene?.screen { return screen.isCaptured }
    return UIScreen.main.isCaptured
  }

  private func startCaptureMonitoring() {
    guard !captureObserverInstalled else { return }
    captureObserverInstalled = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(captureStateChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    // Eine Aufnahme kann schon laufen, bevor der Messenger entsperrt wird —
    // dann kommt keine Benachrichtigung mehr, der Zustand muss aktiv
    // abgefragt werden.
    updateCaptureMask()
  }

  private func stopCaptureMonitoring() {
    guard captureObserverInstalled else { return }
    captureObserverInstalled = false
    NotificationCenter.default.removeObserver(
      self,
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    removeCaptureMask()
  }

  @objc private func captureStateChanged() {
    runOnMain { self.updateCaptureMask() }
  }

  /// Abdeckung nach dem aktuellen Zustand setzen oder entfernen und Dart
  /// informieren.
  fileprivate func updateCaptureMask() {
    let captured = isScreenBeingCaptured
    if captured {
      applyCaptureMask()
    } else {
      removeCaptureMask()
    }
    captureEventSink?(captured)
  }

  /// Alle Aufnahme-Abdeckungen abraeumen.
  ///
  /// Nach Tag statt `viewWithTag`, aus demselben Grund wie bei den
  /// App-Switcher-Abdeckungen: `viewWithTag` liefert nur den ersten Treffer,
  /// und mehrere Zustandswechsel koennen mehrere Abdeckungen hinterlassen —
  /// eine dauerhaft schwarze App ohne Rueckweg.
  private func removeCaptureMask() {
    guard let window = window else { return }
    for view in window.subviews where view.tag == AppDelegate.captureMaskTag {
      view.removeFromSuperview()
    }
  }

  private func applyCaptureMask() {
    guard let window = window else { return }
    removeCaptureMask()
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .black
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.tag = AppDelegate.captureMaskTag
    // Schluckt Beruehrungen: unter einer Abdeckung soll nichts bedienbar
    // sein, was der Nutzer nicht sieht.
    cover.isUserInteractionEnabled = true

    if !captureNoticeText.isEmpty {
      let label = UILabel()
      label.text = captureNoticeText
      label.textColor = .white
      label.numberOfLines = 0
      label.textAlignment = .center
      label.font = .systemFont(ofSize: 17, weight: .medium)
      label.translatesAutoresizingMaskIntoConstraints = false
      cover.addSubview(label)
      NSLayoutConstraint.activate([
        label.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
        label.leadingAnchor.constraint(equalTo: cover.leadingAnchor, constant: 32),
        label.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: -32),
      ])
    }

    window.addSubview(cover)
    window.bringSubviewToFront(cover)
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
      // Eine Aufnahme kann waehrend der Pause gestartet oder beendet worden
      // sein; im Hintergrund kommt die Benachrichtigung nicht zuverlaessig an.
      if self.captureObserverInstalled { self.updateCaptureMask() }
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

// MARK: - Capture EventChannel Stream Handler

/// Meldet Dart, ob der Bildschirm gerade aufgezeichnet oder gespiegelt wird.
class CaptureStreamHandler: NSObject, FlutterStreamHandler {
  weak var delegate: AppDelegate?

  init(delegate: AppDelegate) {
    self.delegate = delegate
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    delegate?.captureEventSink = events
    // Sofort den aktuellen Zustand nachreichen: wer sich anmeldet, waehrend
    // eine Aufnahme schon laeuft, bekaeme sonst bis zum naechsten Wechsel
    // nichts zu sehen.
    delegate?.updateCaptureMask()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    delegate?.captureEventSink = nil
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
