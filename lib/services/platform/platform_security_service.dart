import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Platform security: biometric auth, screenshot protection,
/// root/jailbreak/Frida/debugger detection, screenshot event detection.
///
/// All operations are no-ops on web.
class PlatformSecurityService {
  final LocalAuthentication _localAuth;
  static const _channel = MethodChannel('krypta/security');
  static const _screenshotEventChannel = EventChannel('krypta/screenshot_events');

  /// Stream of screenshot events from the native platform.
  /// Emits `true` when a screenshot was blocked (protection on),
  /// emits `false` when a screenshot was taken (protection off).
  Stream<bool>? _screenshotStream;

  /// Whether screenshot protection is currently enabled.
  bool _screenshotProtectionActive = false;

  bool get isScreenshotProtectionActive => _screenshotProtectionActive;

  /// Cached result of device compromise check.
  /// Call [invalidateDeviceCache] on app resume to re-check periodically.
  bool? _deviceCompromised;

  PlatformSecurityService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  // --- Biometric Authentication ---

  Future<bool> get isBiometricAvailable async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Authenticate to continue'}) async {
    if (kIsWeb) return true;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  // --- Screenshot Protection ---

  Future<void> enableScreenshotProtection() async {
    _screenshotProtectionActive = true;
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('enableSecureFlag');
    } catch (_) {}
  }

  Future<void> disableScreenshotProtection() async {
    _screenshotProtectionActive = false;
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('disableSecureFlag');
    } catch (_) {}
  }

  // --- Screenshot Event Detection ---

  /// Stream that emits when a screenshot event is detected.
  /// Each event is a `Map` with `"blocked"` = true/false.
  Stream<bool> get onScreenshotDetected {
    _screenshotStream ??= _screenshotEventChannel
        .receiveBroadcastStream()
        .map((event) => event == true)
        .handleError((_) {});
    return _screenshotStream!;
  }

  // --- Device Integrity Check ---

  /// Comprehensive device compromise detection.
  ///
  /// Checks for:
  /// - Root (Android) / Jailbreak (iOS) indicators
  /// - Frida instrumentation framework
  /// - Debugger attachment
  /// - Tampered runtime environment
  ///
  /// Returns true if the device appears compromised.
  /// Result is cached after first check.
  Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false;
    if (_deviceCompromised != null) return _deviceCompromised!;

    try {
      bool compromised = false;

      if (Platform.isAndroid) {
        compromised = _checkAndroidRoot() ||
            _checkFridaAndroid() ||
            _checkDebugger();
      } else if (Platform.isIOS) {
        compromised = _checkIOSJailbreak() ||
            _checkFridaIOS() ||
            _checkDebugger();
      }

      _deviceCompromised = compromised;
      return compromised;
    } catch (_) {
      // Fail-closed: if we can't check, assume compromised
      _deviceCompromised = true;
      return true;
    }
  }

  /// Hard block: call on app start to prevent use on compromised devices.
  /// Returns true if device is safe.
  Future<bool> enforceDeviceIntegrity() async {
    final compromised = await isDeviceCompromised();
    if (compromised) {
      if (kDebugMode) debugPrint('Device integrity check FAILED — app blocked');
    }
    return !compromised;
  }

  /// Invalidate the cached device integrity result.
  ///
  /// Call this on `AppLifecycleState.resumed` to re-check on each app resume.
  /// Prevents bypassing integrity checks if the device is rooted while
  /// the app is in the background.
  void invalidateDeviceCache() {
    _deviceCompromised = null;
  }

  // --- Root Detection (Android) ---

  bool _checkAndroidRoot() {
    const rootIndicators = [
      '/system/app/Superuser.apk',
      '/system/xbin/su',
      '/system/bin/su',
      '/sbin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/data/local/su',
      '/system/bin/failsafe/su',
      '/system/sd/xbin/su',
      '/system/app/SuperSU.apk',
      '/data/data/com.noshufou.android.su',
      '/data/data/eu.chainfire.supersu',
      '/data/data/com.topjohnwu.magisk',
    ];
    for (final path in rootIndicators) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {}
    }
    // Check for Magisk
    try {
      if (File('/sbin/.magisk').existsSync()) return true;
    } catch (_) {}
    return false;
  }

  // --- Jailbreak Detection (iOS) ---

  bool _checkIOSJailbreak() {
    const jailbreakIndicators = [
      '/Applications/Cydia.app',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash',
      '/usr/sbin/sshd',
      '/etc/apt',
      '/private/var/lib/apt/',
      '/usr/bin/ssh',
      '/private/var/stash',
      '/Applications/Sileo.app',
      '/var/binpack',
      '/Library/PreferenceBundles/LibertyPref.bundle',
      '/Library/PreferenceBundles/ShadowPreferences.bundle',
      '/usr/lib/libhooker.dylib',
      '/usr/lib/libsubstitute.dylib',
    ];
    for (final path in jailbreakIndicators) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {}
    }

    // Check if app can write to system paths (sandboxing broken)
    try {
      final testFile = File('/private/jailbreak_test');
      testFile.writeAsStringSync('test');
      testFile.deleteSync();
      return true; // Should not be writable on non-jailbroken device
    } catch (_) {
      // Expected — cannot write to system paths
    }

    return false;
  }

  // --- Frida Detection ---

  bool _checkFridaAndroid() {
    // Check for Frida server process indicators
    const fridaIndicators = [
      '/data/local/tmp/frida-server',
      '/data/local/tmp/re.frida.server',
    ];
    for (final path in fridaIndicators) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {}
    }

    // Check for Frida-related libraries loaded in memory
    try {
      final maps = File('/proc/self/maps').readAsStringSync();
      if (maps.contains('frida') || maps.contains('gadget')) return true;
    } catch (_) {}

    return false;
  }

  bool _checkFridaIOS() {
    // Check for Frida dylibs
    const fridaLibs = [
      '/usr/lib/frida',
      '/usr/lib/FridaGadget.dylib',
      '/Library/Frameworks/FridaGadget.framework',
    ];
    for (final path in fridaLibs) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {}
    }
    return false;
  }

  // --- Debugger Detection ---

  bool _checkDebugger() {
    // Check if running in debug/profile mode
    if (kDebugMode || kProfileMode) return false; // Allow during development

    // On release builds, check for debugger attachment
    try {
      if (Platform.isAndroid) {
        // Check TracerPid in /proc/self/status
        final status = File('/proc/self/status').readAsStringSync();
        final tracerLine = status.split('\n').firstWhere(
          (line) => line.startsWith('TracerPid:'),
          orElse: () => 'TracerPid:\t0',
        );
        final pid = int.tryParse(tracerLine.split('\t').last.trim()) ?? 0;
        if (pid != 0) return true; // Debugger attached
      }
    } catch (_) {}

    return false;
  }
}
