import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../device/device_integrity_policy.dart';

/// Hardware security level — what the device actually supports.
enum HardwareSecurityLevel {
  /// StrongBox (Android) or Secure Enclave (iOS) available.
  /// Keys are protected by dedicated tamper-resistant hardware.
  hardwareEnclave,

  /// TEE-backed keystore (Android) or software keychain (iOS).
  /// Keys are in a trusted execution environment, not a dedicated HSM.
  trustedExecution,

  /// No hardware security — software-only key storage.
  /// Device may be an emulator, old hardware, or compromised.
  softwareOnly,
}

/// Binds critical secrets to hardware security modules.
///
/// On supported devices, the database encryption key is additionally
/// wrapped by a non-extractable key stored in:
/// - Android: StrongBox Keymaster (dedicated HSM) or TEE
/// - iOS: Secure Enclave (dedicated crypto coprocessor)
///
/// Even if an attacker dumps the software keychain, the wrapped key
/// cannot be used without the hardware module — the wrapping key
/// never leaves the secure hardware.
///
/// Integration with [DeviceIntegrityPolicyService]:
/// On compromised devices (warnAndDegrade policy), hardware binding is
/// skipped because root/jailbreak may have already extracted keys from
/// the hardware module. In that case, the database key is used directly
/// (current behavior, same as before this feature).
class HardwareSecurityBinding {
  static const _channel = MethodChannel('krypta/security');
  final DeviceIntegrityPolicyService _integrity;

  HardwareSecurityLevel? _detectedLevel;
  bool _isInitialized = false;

  HardwareSecurityBinding({
    required DeviceIntegrityPolicyService integrity,
  }) : _integrity = integrity;

  /// The detected hardware security level.
  HardwareSecurityLevel get level =>
      _detectedLevel ?? HardwareSecurityLevel.softwareOnly;

  /// Whether hardware-backed key binding is available AND safe to use.
  ///
  /// Returns false if:
  /// - Hardware doesn't support it
  /// - Device integrity check says hardware features should be disabled
  /// - Running on web
  bool get isHardwareBindingAvailable {
    if (!_isInitialized) return false;
    if (!_integrity.hardwareFeaturesAvailable) return false;
    return _detectedLevel == HardwareSecurityLevel.hardwareEnclave;
  }

  /// Whether a hardware-bound wrapping key exists and is ready.
  bool _hardwareKeyReady = false;
  bool get isHardwareKeyReady => _hardwareKeyReady && isHardwareBindingAvailable;

  /// Initialize: detect hardware capabilities and prepare wrapping key.
  ///
  /// Call once during app startup, after [DeviceIntegrityPolicyService]
  /// has completed its initial check.
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      _detectedLevel = HardwareSecurityLevel.softwareOnly;
      _isInitialized = true;
      return;
    }

    // Detect hardware security level
    try {
      final hasStrongBox = await _channel.invokeMethod<bool>('isStrongBoxAvailable');
      if (hasStrongBox == true) {
        _detectedLevel = HardwareSecurityLevel.hardwareEnclave;
      } else {
        // Android TEE or iOS without Secure Enclave
        _detectedLevel = HardwareSecurityLevel.trustedExecution;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Hardware security detection failed: $e');
      _detectedLevel = HardwareSecurityLevel.softwareOnly;
    }

    // Check if hardware wrapping key already exists
    if (_detectedLevel == HardwareSecurityLevel.hardwareEnclave) {
      try {
        _hardwareKeyReady =
            await _channel.invokeMethod<bool>('isHardwareKeyReady') ?? false;
      } catch (_) {
        _hardwareKeyReady = false;
      }
    }

    _isInitialized = true;
  }

  /// Create a hardware-bound wrapping key if the device supports it.
  ///
  /// Returns true if a hardware key was created (or already exists).
  /// Returns false if hardware binding is not available.
  ///
  /// Call after [initialize] and after confirming [isHardwareBindingAvailable].
  Future<bool> createHardwareKey() async {
    if (!isHardwareBindingAvailable) return false;

    try {
      final created =
          await _channel.invokeMethod<bool>('createHardwareBoundKey');
      _hardwareKeyReady = created ?? false;
      return _hardwareKeyReady;
    } catch (e) {
      if (kDebugMode) debugPrint('Hardware key creation failed: $e');
      _hardwareKeyReady = false;
      return false;
    }
  }

  /// Wrap (encrypt) a key using the hardware-bound wrapping key.
  ///
  /// The returned bytes can only be unwrapped on this device, using the
  /// non-extractable key in the secure hardware module.
  ///
  /// Returns null if hardware binding is not available — caller should
  /// fall back to storing the key directly in the software keychain.
  Future<Uint8List?> wrapKey(Uint8List plainKey) async {
    if (!isHardwareKeyReady) return null;

    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'wrapKey',
        {'key': plainKey},
      );
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('Key wrapping failed: $e');
      return null;
    }
  }

  /// Unwrap (decrypt) a key using the hardware-bound wrapping key.
  ///
  /// Returns null if unwrapping fails (hardware key deleted, device reset,
  /// or wrapped key corrupted).
  Future<Uint8List?> unwrapKey(Uint8List wrappedKey) async {
    if (!isHardwareKeyReady) return null;

    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'unwrapKey',
        {'wrapped': wrappedKey},
      );
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('Key unwrapping failed: $e');
      return null;
    }
  }

  /// Delete the hardware-bound wrapping key.
  ///
  /// Call on emergency wipe. After this, any wrapped keys become
  /// permanently inaccessible (the wrapping key is non-extractable
  /// and cannot be recreated with the same value).
  Future<void> deleteHardwareKey() async {
    try {
      await _channel.invokeMethod('deleteHardwareBoundKey');
      _hardwareKeyReady = false;
    } catch (e) {
      if (kDebugMode) debugPrint('Hardware key deletion failed: $e');
    }
  }

  /// Human-readable description of the hardware security level.
  String get levelDescription => switch (_detectedLevel) {
        HardwareSecurityLevel.hardwareEnclave =>
          'Hardware-Enklave (StrongBox/Secure Enclave)',
        HardwareSecurityLevel.trustedExecution =>
          'Trusted Execution Environment',
        HardwareSecurityLevel.softwareOnly => 'Software-Schlüsselspeicher',
        null => 'Nicht initialisiert',
      };
}
