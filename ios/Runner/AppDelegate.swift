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
  private let secureMaskField = UITextField()
  private var secureMaskInstalled = false
  /// The secure-canvas layer that masks captures, and the window layer's
  /// original parent — cached so a toggle can re-verify the reparenting is
  /// still intact and rebuild it if UIKit ever swapped the field's sublayers.
  private var secureCanvasLayer: CALayer?
  private var savedOriginalSuperlayer: CALayer?

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

    let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      .privateKeyUsage,
      nil
    )!

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
    return privateKey != nil
  }

  /// Wrap a key using ECIES with the Secure Enclave public key.
  private func wrapKey(_ plainKey: Data) -> FlutterStandardTypedData? {
    guard let privateKey = loadHardwareKey(),
          let publicKey = SecKeyCopyPublicKey(privateKey) else {
      return nil
    }

    var error: Unmanaged<CFError>?
    guard let encrypted = SecKeyCreateEncryptedData(
      publicKey,
      .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
      plainKey as CFData,
      &error
    ) else {
      return nil
    }

    return FlutterStandardTypedData(bytes: encrypted as Data)
  }

  /// Unwrap a key using ECIES with the Secure Enclave private key.
  private func unwrapKey(_ wrapped: Data) -> FlutterStandardTypedData? {
    guard let privateKey = loadHardwareKey() else { return nil }

    var error: Unmanaged<CFError>?
    guard let decrypted = SecKeyCreateDecryptedData(
      privateKey,
      .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
      wrapped as CFData,
      &error
    ) else {
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
  /// installed and verified. If a future iOS release ever stops honoring
  /// this, install fails CLOSED here (we report no protection) and the
  /// post-hoc screenshot detection still warns the user honestly.
  @discardableResult
  private func installSecureMaskIfNeeded() -> Bool {
    if secureMaskInstalled { return true }
    guard let window = window else { return false }
    // Reuse the cached original parent on reinstall so we never treat a
    // broken secure canvas as the "original" superlayer.
    guard let originalSuperlayer = savedOriginalSuperlayer ?? window.layer.superlayer
    else { return false }
    savedOriginalSuperlayer = originalSuperlayer

    secureMaskField.isUserInteractionEnabled = false
    if secureMaskField.superview == nil {
      secureMaskField.translatesAutoresizingMaskIntoConstraints = false
      window.addSubview(secureMaskField)
      NSLayoutConstraint.activate([
        secureMaskField.centerXAnchor.constraint(equalTo: window.centerXAnchor),
        secureMaskField.centerYAnchor.constraint(equalTo: window.centerYAnchor),
      ])
    }

    // The secure render canvas only exists once isSecureTextEntry is on, so
    // force it on and lay out BEFORE looking the canvas layer up.
    secureMaskField.isSecureTextEntry = true
    secureMaskField.layoutIfNeeded()

    guard let canvas = secureMaskField.layer.sublayers?.last else {
      return false // canvas not created on this iOS version — fail closed
    }

    // Reparent: put the field's layer where the window layer was, then nest
    // the window layer inside the secure canvas. addSublayer detaches the
    // window layer from any previous (possibly stale) parent automatically.
    originalSuperlayer.addSublayer(secureMaskField.layer)
    canvas.addSublayer(window.layer)

    // Verify the move actually took; otherwise restore and report failure.
    guard window.layer.superlayer === canvas else {
      originalSuperlayer.addSublayer(window.layer)
      return false
    }

    secureCanvasLayer = canvas
    secureMaskInstalled = true
    return true
  }

  /// True iff the reparenting is still structurally intact: the window layer
  /// sits under the secure canvas, which sits under the field's layer. UIKit
  /// can rebuild a secure field's sublayers across toggles, so we re-check.
  private func isSecureMaskStructureIntact() -> Bool {
    guard let canvas = secureCanvasLayer, let window = window else { return false }
    return window.layer.superlayer === canvas
        && canvas.superlayer === secureMaskField.layer
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
      // If a prior install's structure was torn down by UIKit, rebuild once.
      if ok && !self.isSecureMaskStructureIntact() {
        self.secureMaskInstalled = false
        ok = self.installSecureMaskIfNeeded()
      }
      if ok {
        self.secureMaskField.isSecureTextEntry = on
        // A toggle can rebuild sublayers — confirm it survived.
        ok = self.isSecureMaskStructureIntact()
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

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // Keep the black mask one runloop tick longer than strictly needed,
    // so Flutter has time to render the Calculator frame after our
    // background-lock logic in app.dart resets the route. This avoids a
    // flash of the previous (now stale) screen content during resume.
    DispatchQueue.main.async {
      self.window?.viewWithTag(9999)?.removeFromSuperview()
    }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    // Cover the screen with an opaque black view so the iOS app-switcher
    // snapshot and any transient inactive-state frames render as solid
    // black instead of leaking the messenger UI or showing a white flash.
    guard let window = window else { return }
    let blackView = UIView(frame: window.bounds)
    blackView.backgroundColor = .black
    blackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blackView.tag = 9999
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
