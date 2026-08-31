import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/sync_lifecycle_policy.dart';

/// Wann der Inbox-Listener abgebaut und wann er wieder angehaengt wird.
///
/// Der Anlass: bisher lief er beim Wechsel in den Hintergrund einfach weiter,
/// und beim Aufwachen holte ihn niemand zurueck. Das Aufwachen muss der eine
/// klar definierte Einstiegspunkt sein.
void main() {
  group('Abbauen', () {
    test('der Wechsel in den Hintergrund baut ab', () {
      expect(SyncLifecyclePolicy.shouldPause(AppLifecycleState.paused), isTrue);
    });

    test('eine verdeckte App baut ab', () {
      expect(SyncLifecyclePolicy.shouldPause(AppLifecycleState.hidden), isTrue);
    });

    test('eine kurze Unterbrechung baut NICHT ab', () {
      // `inactive` feuert beim Screenshot, bei der Berechtigungsabfrage, beim
      // Blick ins Kontrollzentrum und bei einem eingehenden Anruf. Wuerde das
      // den Listener abbauen, kostete jeder dieser Griffe eine Zustellung.
      expect(
        SyncLifecyclePolicy.shouldPause(AppLifecycleState.inactive),
        isFalse,
      );
    });
  });

  group('Wieder anhaengen', () {
    test('das Aufwachen haengt wieder an', () {
      expect(
        SyncLifecyclePolicy.shouldResume(AppLifecycleState.resumed),
        isTrue,
      );
    });

    test('eine kurze Unterbrechung haengt nichts neu an', () {
      expect(
        SyncLifecyclePolicy.shouldResume(AppLifecycleState.inactive),
        isFalse,
      );
    });

    test('kein Zustand baut ab und haengt zugleich wieder an', () {
      for (final zustand in AppLifecycleState.values) {
        expect(
          SyncLifecyclePolicy.shouldPause(zustand) &&
              SyncLifecyclePolicy.shouldResume(zustand),
          isFalse,
          reason: 'widerspruechlich bei $zustand',
        );
      }
    });
  });
}
