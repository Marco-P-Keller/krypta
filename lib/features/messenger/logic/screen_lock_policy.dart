import 'package:flutter/widgets.dart';

/// Wann die App auf den Taschenrechner zurueckfaellt — und wann sie den Chat
/// wieder hervorholt.
///
/// Bisher wurde nur bei `paused`/`hidden` gesperrt. Ein sehr schneller Wechsel
/// erzeugt auf iOS aber oft nur `inactive`: die Abdeckung ging hoch und wieder
/// runter, umgeschaltet wurde nie — und man landete zurueck im offenen Chat.
/// Eine Sperre, die davon abhaengt, wie lange jemand weg war, ist keine.
///
/// Einfach bei `inactive` mitzusperren geht aber auch nicht. Dasselbe Ereignis
/// feuert beim Screenshot, bei der Berechtigungsabfrage, beim Blick ins
/// Kontrollzentrum und bei einem eingehenden Anruf. Wer nur die Helligkeit
/// nachsieht, will nicht auf dem Taschenrechner landen.
///
/// Deshalb in zwei Schritten:
///
/// 1. **Frueh sperren**, schon bei `inactive`. Sichtbar ist davon nichts — die
///    Abdeckung liegt zu diesem Zeitpunkt ohnehin ueber dem Fenster.
/// 2. **Beim Aufwachen zurueckholen**, wenn die App zwischendurch nie wirklich
///    im Hintergrund war. Das entscheidet [marksBackgrounded], nicht die Zeit.
abstract final class ScreenLockPolicy {
  /// Ob in diesem Zustand auf den Taschenrechner umzuschalten ist.
  static bool shouldLock(AppLifecycleState state) =>
      state != AppLifecycleState.resumed;

  /// Ob beim Aufwachen der vorherige Bildschirm zurueckzuholen ist.
  ///
  /// Nur wenn die App nie wirklich weg war. Nach einem echten Wechsel in den
  /// Hintergrund bleibt der Taschenrechner stehen und verlangt den Code.
  static bool shouldRestore(
    AppLifecycleState state, {
    required bool wasBackgrounded,
  }) =>
      state == AppLifecycleState.resumed && !wasBackgrounded;

  /// Ob dieser Zustand als „die App war wirklich weg" zaehlt.
  ///
  /// `inactive` zaehlt ausdruecklich **nicht** — sonst waere das Zurueckholen
  /// wirkungslos und jeder Blick ins Kontrollzentrum endete auf dem
  /// Taschenrechner.
  static bool marksBackgrounded(AppLifecycleState state) =>
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.detached;
}
