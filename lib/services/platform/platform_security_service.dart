import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Platform security: biometric auth, screenshot protection, root/jailbreak detection.
/// All operations are no-ops on web.
class PlatformSecurityService {
  final LocalAuthentication _localAuth;

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
    if (kIsWeb) return;
    try {
      await const MethodChannel('krypta/security')
          .invokeMethod('enableSecureFlag');
    } catch (_) {}
  }

  Future<void> disableScreenshotProtection() async {
    if (kIsWeb) return;
    try {
      await const MethodChannel('krypta/security')
          .invokeMethod('disableSecureFlag');
    } catch (_) {}
  }

  // --- Root / Jailbreak Detection ---

  /// Checks for signs of a rooted/jailbroken device.
  ///
  /// Not foolproof but raises the bar for casual exploitation.
  /// Returns true if the device appears compromised.
  Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) return _checkAndroidRoot();
      if (Platform.isIOS) return _checkIOSJailbreak();
    } catch (_) {}
    return false;
  }

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
    ];
    for (final path in rootIndicators) {
      if (File(path).existsSync()) return true;
    }
    // Check for Magisk
    try {
      if (File('/sbin/.magisk').existsSync()) return true;
    } catch (_) {}
    return false;
  }

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
    ];
    for (final path in jailbreakIndicators) {
      if (File(path).existsSync()) return true;
    }
    return false;
  }
}
