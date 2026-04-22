import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let securityChannel = "krypta/security"

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
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Method Channel Handler

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enableSecureFlag":
      // iOS uses blur overlay approach instead of FLAG_SECURE
      result(true)
    case "disableSecureFlag":
      result(true)
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
    return (item as! SecKey)
  }

  // MARK: - Screenshot & Screen Recording Protection

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // Remove blur overlay when returning to foreground
    window?.viewWithTag(9999)?.removeFromSuperview()
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    // Add blur overlay to prevent task switcher screenshot
    guard let window = window else { return }
    let blurEffect = UIBlurEffect(style: .light)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.frame = window.bounds
    blurView.tag = 9999
    window.addSubview(blurView)
  }
}
