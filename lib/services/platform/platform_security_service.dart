import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Platform security: biometric auth + screenshot protection.
/// All operations are no-ops on web.
class PlatformSecurityService {
  final LocalAuthentication _localAuth;

  PlatformSecurityService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

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
}
