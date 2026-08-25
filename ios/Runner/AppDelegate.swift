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

  // Aufnahme-/Spiegelungserkennung.
  private var captureObserverInstalled = false

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
      // Es wird nichts mehr maskiert — nur noch erkannt und gemeldet.
      // Screenshots lassen sich auf iOS ohnehin nicht verhindern, und der
      // Versuch, den Inhalt zu schwaerzen, wirkte ab iOS 26 nicht mehr.
      isSecureFlagEnabled = true
      startScreenshotDetection()
      startCaptureMonitoring()
      result(true)
    case "disableSecureFlag":
      isSecureFlagEnabled = false
      stopCaptureMonitoring()
      stopScreenshotDetection()
      result(true)
    case "isScreenCaptured":
      result(isScreenBeingCaptured)
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

  // MARK: - Bildschirmaufnahme und Spiegelung erkennen

  /// Ob der Bildschirm gerade aufgezeichnet oder gespiegelt wird.
  ///
  /// `UIScreen.isCaptured` ist der dokumentierte, von Apple unterstuetzte Weg.
  /// Verhindern laesst sich eine Aufnahme damit nicht — nur feststellen. Genau
  /// das ist der Punkt: die App maskiert nichts mehr, sondern sagt beiden
  /// Seiten Bescheid.
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
    reportCaptureState()
  }

  private func stopCaptureMonitoring() {
    guard captureObserverInstalled else { return }
    captureObserverInstalled = false
    NotificationCenter.default.removeObserver(
      self,
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
  }

  @objc private func captureStateChanged() {
    runOnMain { self.reportCaptureState() }
  }

  /// Den aktuellen Aufnahmezustand an Dart melden.
  fileprivate func reportCaptureState() {
    captureEventSink?(isScreenBeingCaptured)
  }

  /// Layer- und View-Baum duerfen nur auf dem Hauptthread angefasst werden.
  private func runOnMain(_ work: @escaping () -> Void) {
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
      // Eine Aufnahme kann waehrend der Pause gestartet oder beendet worden
      // sein; im Hintergrund kommt die Benachrichtigung nicht zuverlaessig an.
      if self.captureObserverInstalled { self.reportCaptureState() }
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

  /// NotificationCenter fasst mehrfaches Registrieren NICHT zusammen: wer
  /// denselben Beobachter zweimal anmeldet, bekommt jede Meldung zweimal.
  /// Genau das passierte auf Build 90 — `enableSecureFlag` meldete an, und
  /// der Stream-Handler tat es beim Zuhoeren gleich noch einmal. Ein
  /// Screenshot erzeugte dadurch zwei Hinweise, und die Gegenseite bekam
  /// zwei Meldungen.
  private var screenshotObserverInstalled = false

  func startScreenshotDetection() {
    guard !screenshotObserverInstalled else { return }
    screenshotObserverInstalled = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
  }

  func stopScreenshotDetection() {
    guard screenshotObserverInstalled else { return }
    screenshotObserverInstalled = false
    NotificationCenter.default.removeObserver(
      self,
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
  }

  @objc private func screenshotTaken() {
    // iOS meldet einen Screenshot erst NACH der Aufnahme und laesst ihn nicht
    // verhindern. Der Wert ist deshalb immer `false`: nichts wurde blockiert.
    // Dart macht daraus einen Eintrag im Verlauf — auf beiden Seiten.
    screenshotEventSink?(false)
  }
}

// MARK: - Screenshot EventChannel Stream Handler

class ScreenshotStreamHandler: NSObject, FlutterStreamHandler {
  weak var delegate: AppDelegate?

  init(delegate: AppDelegate) {
    self.delegate = delegate
  }

  // Nur die Leitung, nicht der Schalter: ob ueberhaupt erkannt wird,
  // entscheiden `enableSecureFlag` und `disableSecureFlag` — so wie bei der
  // Bildschirmaufnahme auch. Wuerde das Zuhoeren die Erkennung selbst
  // starten, liefe sie wieder an, sobald ein Chat geoeffnet wird, obwohl der
  // Nutzer den Hinweis abgeschaltet hat.
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    delegate?.screenshotEventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    delegate?.screenshotEventSink = nil
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
    delegate?.reportCaptureState()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    delegate?.captureEventSink = nil
    return nil
  }
}
