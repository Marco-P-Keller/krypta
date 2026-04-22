import 'package:flutter/foundation.dart';
import '../../services/platform/platform_security_service.dart';

/// Device integrity policy — defines how the app responds to
/// a compromised device (root/jailbreak/Frida/debugger).
///
/// Policy levels (strictest → most lenient):
/// 1. [block] — App refuses to operate. Messenger is inaccessible.
/// 2. [warnAndDegrade] — App shows persistent warning, disables
///    hardware-backed features, marks sessions as potentially compromised.
/// 3. [warnOnly] — Show a warning but allow full operation.
///
/// The default policy is [warnAndDegrade] — balanced between security
/// and usability. Users on rooted/jailbroken devices can still
/// communicate, but are clearly warned and lose hardware protections.
enum DeviceIntegrityPolicy {
  /// Hard block — app shows calculator only, messenger inaccessible.
  block,

  /// Warning + degradation — show warning, disable hardware-backed keys.
  warnAndDegrade,

  /// Warning only — inform user, but allow full operation.
  warnOnly,
}

enum DeviceIntegrityLevel {
  /// Device is clean — all features enabled.
  clean,

  /// Device shows compromise indicators — security degraded.
  compromised,

  /// Integrity check failed or couldn't run — assume worst case.
  unknown,
}

/// Result of a device integrity assessment.
class DeviceIntegrityResult {
  final DeviceIntegrityLevel level;
  final DateTime checkedAt;

  const DeviceIntegrityResult({
    required this.level,
    required this.checkedAt,
  });

  bool get isClean => level == DeviceIntegrityLevel.clean;
  bool get isCompromised => level == DeviceIntegrityLevel.compromised;
  bool get isUnknown => level == DeviceIntegrityLevel.unknown;

  /// Whether the device is NOT clean (compromised or unknown).
  bool get isThreat => !isClean;
}

/// What the app should do based on integrity check + policy.
enum DeviceIntegrityAction {
  /// Device is clean — proceed normally.
  allow,

  /// Device compromised — hard block all access.
  block,

  /// Device compromised — warn user, degrade hardware features.
  warnAndDegrade,

  /// Device compromised — warn user, allow full operation.
  warnOnly,
}

/// Manages device integrity policy enforcement.
///
/// Checks device integrity and enforces the configured policy:
/// - On app start: full integrity check
/// - On app resume: re-check (invalidate cache)
/// - Result is stored and queryable by other components
///
/// The policy is fixed at construction — it cannot be weakened at runtime
/// to prevent a compromised device from downgrading its own enforcement.
class DeviceIntegrityPolicyService {
  final PlatformSecurityService _platform;
  final DeviceIntegrityPolicy _policy;
  DeviceIntegrityResult? _lastResult;

  DeviceIntegrityPolicyService({
    required PlatformSecurityService platform,
    DeviceIntegrityPolicy policy = DeviceIntegrityPolicy.warnAndDegrade,
  })  : _platform = platform,
        _policy = policy;

  /// The configured policy (immutable after construction).
  DeviceIntegrityPolicy get policy => _policy;

  /// Last known integrity result.
  DeviceIntegrityResult? get lastResult => _lastResult;

  /// Whether the device is currently considered clean.
  bool get isDeviceClean => _lastResult?.isClean ?? false;

  /// Whether the device is currently considered compromised or unknown.
  bool get isDeviceThreat => _lastResult?.isThreat ?? true;

  /// Run a full device integrity check and return the result.
  ///
  /// Call on app start and app resume.
  Future<DeviceIntegrityResult> checkIntegrity() async {
    try {
      final compromised = await _platform.isDeviceCompromised();
      _lastResult = DeviceIntegrityResult(
        level: compromised
            ? DeviceIntegrityLevel.compromised
            : DeviceIntegrityLevel.clean,
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      // Fail-closed: if the check itself fails, assume compromised.
      if (kDebugMode) debugPrint('Device integrity check failed: $e');
      _lastResult = DeviceIntegrityResult(
        level: DeviceIntegrityLevel.unknown,
        checkedAt: DateTime.now(),
      );
    }
    return _lastResult!;
  }

  /// Determine what action the app should take based on the last
  /// integrity check and the configured policy.
  ///
  /// Must call [checkIntegrity] at least once before calling this.
  DeviceIntegrityAction enforce() {
    final result = _lastResult;
    if (result == null || result.isClean) return DeviceIntegrityAction.allow;

    // Device is compromised or unknown — apply policy.
    return switch (_policy) {
      DeviceIntegrityPolicy.block => DeviceIntegrityAction.block,
      DeviceIntegrityPolicy.warnAndDegrade =>
        DeviceIntegrityAction.warnAndDegrade,
      DeviceIntegrityPolicy.warnOnly => DeviceIntegrityAction.warnOnly,
    };
  }

  /// Invalidate and re-check on app resume.
  ///
  /// Call from `AppLifecycleState.resumed` handler.
  Future<DeviceIntegrityResult> recheck() async {
    _platform.invalidateDeviceCache();
    return checkIntegrity();
  }

  /// Whether hardware-backed features should be available.
  ///
  /// On compromised devices, Secure Enclave / StrongBox may be
  /// bypassed by the root/jailbreak tooling. Disable these features
  /// and fall back to software-only key storage.
  ///
  /// With [warnOnly] policy, hardware features remain available
  /// (the user accepts the risk). With [block] or [warnAndDegrade],
  /// hardware features are disabled on compromised devices.
  bool get hardwareFeaturesAvailable {
    if (isDeviceClean) return true;
    return _policy == DeviceIntegrityPolicy.warnOnly;
  }
}
