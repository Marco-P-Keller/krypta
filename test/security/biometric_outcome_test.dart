import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:kryptaapp/services/platform/biometric_outcome.dart';

/// Wie das Ergebnis einer Face-ID-Abfrage gelesen wird.
///
/// Der Unterschied zwischen „abgelehnt" und „ging nicht" ist hier kein
/// Detail: nur eine Ablehnung zählt auf den Fehlversuchszähler, und der
/// löst bei fünf Versuchen die **Notfall-Löschung** aus. Ein Gerät, das
/// gerade nicht prüfen kann, darf niemandem die Daten vernichten.
void main() {
  test('erkannt heisst erkannt', () {
    expect(readBiometricResult(true, null), BiometricOutcome.success);
  });

  test('nicht erkannt ist eine Ablehnung', () {
    expect(readBiometricResult(false, null), BiometricOutcome.refused);
  });

  group('Abbruch zaehlt nicht als Fehlversuch', () {
    for (final code in [
      LocalAuthExceptionCode.userCanceled,
      LocalAuthExceptionCode.systemCanceled,
      LocalAuthExceptionCode.timeout,
      LocalAuthExceptionCode.authInProgress,
      LocalAuthExceptionCode.uiUnavailable,
      LocalAuthExceptionCode.userRequestedFallback,
    ]) {
      test(code.name, () {
        expect(
          readBiometricResult(null, LocalAuthException(code: code)),
          BiometricOutcome.cancelled,
        );
      });
    }
  });

  group('„geht gerade nicht" zaehlt auch nicht', () {
    for (final code in [
      LocalAuthExceptionCode.noCredentialsSet,
      LocalAuthExceptionCode.noBiometricsEnrolled,
      LocalAuthExceptionCode.noBiometricHardware,
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable,
      LocalAuthExceptionCode.temporaryLockout,
      LocalAuthExceptionCode.biometricLockout,
      LocalAuthExceptionCode.deviceError,
      LocalAuthExceptionCode.unknownError,
    ]) {
      test(code.name, () {
        expect(
          readBiometricResult(null, LocalAuthException(code: code)),
          BiometricOutcome.unavailable,
        );
      });
    }
  });

  test('ein fremder Fehler gilt als „geht nicht", nicht als Ablehnung', () {
    // Fail-safe in Richtung Daten: im Zweifel niemandem den Zaehler
    // hochtreiben, der am Ende alles loescht.
    expect(readBiometricResult(null, StateError('irgendwas')),
        BiometricOutcome.unavailable);
  });

  test('nur eine Ablehnung zaehlt auf den Zaehler', () {
    expect(BiometricOutcome.refused.countsAsFailedAttempt, isTrue);
    for (final o in [
      BiometricOutcome.success,
      BiometricOutcome.cancelled,
      BiometricOutcome.unavailable,
    ]) {
      expect(o.countsAsFailedAttempt, isFalse, reason: o.name);
    }
  });
}
