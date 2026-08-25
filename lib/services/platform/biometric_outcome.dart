import 'package:local_auth/local_auth.dart';

/// Wie eine Face-ID- bzw. Touch-ID-Abfrage ausgegangen ist.
///
/// Der Unterschied zwischen „abgelehnt" und „ging nicht" ist hier kein
/// Detail: nur eine Ablehnung zählt auf den Fehlversuchszähler, und der löst
/// bei fünf Versuchen die Notfall-Löschung aus. Ein Gerät, das gerade nicht
/// prüfen kann, darf niemandem die Daten vernichten.
enum BiometricOutcome {
  /// Erkannt.
  success,

  /// Nicht erkannt — ein falsches Gesicht, ein falscher Finger.
  refused,

  /// Abgebrochen: vom Nutzer, vom System, oder abgelaufen.
  cancelled,

  /// Ging nicht: nichts eingerichtet, keine Hardware, gesperrt.
  unavailable;

  /// Ob das auf den Fehlversuchszähler zählt.
  bool get countsAsFailedAttempt => this == BiometricOutcome.refused;
}

/// Das Ergebnis von `LocalAuthentication.authenticate` lesen.
///
/// [result] ist der Rückgabewert, [error] das Geworfene — genau eines von
/// beidem ist gesetzt.
BiometricOutcome readBiometricResult(bool? result, Object? error) {
  if (error == null) {
    return result == true ? BiometricOutcome.success : BiometricOutcome.refused;
  }

  if (error is! LocalAuthException) {
    // Etwas Unerwartetes. Im Zweifel nicht zählen: der Zähler löscht am Ende
    // alles, und dafür braucht es Gewissheit, nicht eine Vermutung.
    return BiometricOutcome.unavailable;
  }

  return switch (error.code) {
    LocalAuthExceptionCode.userCanceled ||
    LocalAuthExceptionCode.systemCanceled ||
    LocalAuthExceptionCode.timeout ||
    LocalAuthExceptionCode.authInProgress ||
    LocalAuthExceptionCode.uiUnavailable ||
    // Tritt nur auf, wenn die Abfrage biometrieonly läuft — dann hat der
    // Nutzer auf „Passwort nutzen" getippt und das System durfte es nicht
    // anbieten. Genau der Fall, der Daniel aus der App geworfen hat.
    LocalAuthExceptionCode.userRequestedFallback =>
      BiometricOutcome.cancelled,
    _ => BiometricOutcome.unavailable,
  };
}
