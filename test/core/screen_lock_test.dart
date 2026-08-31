import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/screen_lock_policy.dart';

/// Wann die App auf den Taschenrechner zurueckfaellt — und wann nicht.
///
/// Der Anlass: bei einem sehr schnellen Wechsel landete man wieder direkt im
/// Chat. Gesperrt wurde nur bei `paused`/`hidden`; ein kurzer Wechsel erzeugt
/// auf iOS aber oft nur `inactive`, und dann blieb der Messenger stehen.
///
/// Einfach bei `inactive` mitzusperren geht nicht: dasselbe Ereignis feuert
/// beim Screenshot, bei der Berechtigungsabfrage, beim Blick ins
/// Kontrollzentrum und bei einem eingehenden Anruf. Wer nur die Helligkeit
/// nachsieht, will nicht auf dem Taschenrechner landen.
///
/// Deshalb zwei Schritte: **frueh sperren**, solange die Abdeckung ohnehin
/// oben ist und niemand etwas sieht — und beim Aufwachen **zurueckholen**,
/// wenn die App zwischendurch nie wirklich im Hintergrund war.
void main() {
  group('Sperren', () {
    test('ein kurzes Wegschalten sperrt bereits', () {
      // Genau der gemeldete Fehler: hier passierte bisher nichts.
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.inactive), isTrue);
    });

    test('der Wechsel in den Hintergrund sperrt', () {
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.paused), isTrue);
    });

    test('eine verdeckte App sperrt', () {
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.hidden), isTrue);
    });

    test('das Aufwachen sperrt nicht', () {
      expect(ScreenLockPolicy.shouldLock(AppLifecycleState.resumed), isFalse);
    });
  });

  group('Zurueckholen', () {
    test('war die App nie wirklich weg, kommt der Chat zurueck', () {
      // Kontrollzentrum auf und zu, Screenshot, Anruf-Banner: `inactive` kam,
      // `paused` nie. Der Nutzer hat die App nicht verlassen.
      expect(
        ScreenLockPolicy.shouldRestore(
          AppLifecycleState.resumed,
          wasBackgrounded: false,
        ),
        isTrue,
      );
    });

    test('war sie wirklich weg, bleibt der Taschenrechner', () {
      expect(
        ScreenLockPolicy.shouldRestore(
          AppLifecycleState.resumed,
          wasBackgrounded: true,
        ),
        isFalse,
      );
    });

    test('ohne Aufwachen wird nie zurueckgeholt', () {
      for (final zustand in AppLifecycleState.values) {
        if (zustand == AppLifecycleState.resumed) continue;
        expect(
          ScreenLockPolicy.shouldRestore(zustand, wasBackgrounded: false),
          isFalse,
          reason: 'unerwartet bei $zustand',
        );
      }
    });
  });

  group('Was als „wirklich weg" zaehlt', () {
    test('paused und hidden zaehlen', () {
      expect(ScreenLockPolicy.marksBackgrounded(AppLifecycleState.paused),
          isTrue);
      expect(ScreenLockPolicy.marksBackgrounded(AppLifecycleState.hidden),
          isTrue);
    });

    test('ein kurzes Wegschalten zaehlt NICHT', () {
      // Sonst waere das Zurueckholen wirkungslos und der Kontrollzentrum-Blick
      // landete weiterhin auf dem Taschenrechner.
      expect(ScreenLockPolicy.marksBackgrounded(AppLifecycleState.inactive),
          isFalse);
    });

    test('detached zaehlt — die App wird abgeraeumt', () {
      expect(ScreenLockPolicy.marksBackgrounded(AppLifecycleState.detached),
          isTrue);
    });
  });
}
