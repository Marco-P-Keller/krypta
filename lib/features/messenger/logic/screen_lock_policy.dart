import 'package:flutter/widgets.dart';

/// Wann die App auf den Taschenrechner zurueckfaellt.
///
/// **Nur wenn sie wirklich im Hintergrund war.** Ein `inactive` allein zaehlt
/// nicht: dasselbe Ereignis feuert beim Screenshot, beim Blick ins
/// Kontrollzentrum, bei einem eingehenden Anruf — und beim Face-ID-Dialog.
///
/// Am 31.08. war das kurzzeitig anders. Da wurde schon bei `inactive` gesperrt
/// und beim Aufwachen zurueckgeholt, um auch den sehr schnellen App-Wechsel zu
/// erwischen. Auf dem Geraet hat das zwei Dinge kaputtgemacht: der
/// Taschenrechner blitzte bei jedem Screenshot und jedem Kontrollzentrum kurz
/// auf, weil unter der Abdeckung wirklich umgeschaltet wurde — und Face ID kam
/// nie durch, weil der Systemdialog `inactive` erzeugt, das Sperren den
/// Sperrzaehler hochzaehlte und die laufende Anmeldung danach als verfallen
/// galt. Nach jeder erfolgreichen Erkennung landete man wieder auf dem
/// Taschenrechner.
///
/// Beides ist der Preis dafuer, ein Ereignis zu behandeln, das mehrere
/// Bedeutungen hat. **Der sehr schnelle App-Wechsel bleibt deshalb offen** —
/// von einem Screenshot ist er nicht zu unterscheiden. Sichtbar wird der
/// Messenger dabei fuer niemanden: die Vorschau im App-Umschalter deckt ein
/// eigener Mechanismus ab.
abstract final class ScreenLockPolicy {
  /// Ob in diesem Zustand auf den Taschenrechner umzuschalten ist.
  static bool shouldLock(AppLifecycleState state) => marksBackgrounded(state);

  /// Ob dieser Zustand als „die App war wirklich weg" zaehlt.
  static bool marksBackgrounded(AppLifecycleState state) =>
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.detached;
}
