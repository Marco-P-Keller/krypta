import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/screen_lock_policy.dart';

/// Wann die App auf den Taschenrechner zurueckfaellt.
///
/// **Nur wenn sie wirklich im Hintergrund war.** Ein `inactive` allein zaehlt
/// nicht: dasselbe Ereignis feuert beim Screenshot, beim Blick ins
/// Kontrollzentrum, bei einem eingehenden Anruf — und beim Face-ID-Dialog.
///
/// Das war am 31.08. kurzzeitig anders. Da wurde schon bei `inactive` gesperrt
/// und beim Aufwachen zurueckgeholt, in der Hoffnung, damit auch den sehr
/// schnellen App-Wechsel zu erwischen. Auf dem Geraet hat das zwei Dinge
/// kaputtgemacht:
///
/// - Der Taschenrechner blitzte bei jedem Screenshot und jedem Blick ins
///   Kontrollzentrum kurz auf, weil unter der Abdeckung wirklich umgeschaltet
///   wurde.
/// - Face ID kam nie durch. Der Systemdialog erzeugt `inactive`, das Sperren
///   zaehlte den Sperrzaehler hoch, und die laufende Anmeldung galt danach als
///   verfallen — nach jeder erfolgreichen Erkennung landete man wieder auf dem
///   Taschenrechner.
///
/// Beides ist der Preis dafuer, ein Ereignis zu behandeln, das mehrere
/// Bedeutungen hat. Der sehr schnelle App-Wechsel bleibt deshalb offen; von
/// einem Screenshot ist er nicht zu unterscheiden.
void main() {
  group('Sperren', () {
    test('der Wechsel in den Hintergrund sperrt', () {
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.paused), isTrue);
    });

    test('eine verdeckte App sperrt', () {
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.hidden), isTrue);
    });

    test('das Abraeumen der App sperrt', () {
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.detached), isTrue);
    });

    test('ein kurzes Wegschalten sperrt NICHT', () {
      // Screenshot, Kontrollzentrum, Anruf-Banner, Face-ID-Dialog.
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.inactive), isFalse);
    });

    test('das Aufwachen sperrt nicht', () {
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.resumed), isFalse);
    });
  });

  group('Was als wirklich weg zaehlt', () {
    test('deckt sich mit dem Sperren', () {
      // Faellt das auseinander, ist wieder ein Zwischenzustand entstanden, in
      // dem umgeschaltet wird, ohne dass jemand die App verlassen hat.
      for (final zustand in AppLifecycleState.values) {
        expect(
          ScreenLockPolicy.shouldLock(zustand),
          ScreenLockPolicy.marksBackgrounded(zustand),
          reason: 'auseinander bei $zustand',
        );
      }
    });
  });
}
