import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/key_publish_status.dart';

/// Warum es das gibt:
///
/// Wenn der eigene Identity-Key oder das PreKey-Bundle nicht auf dem Server
/// landen, kann niemand eine Session zu einem aufbauen — Nachrichten kommen
/// nie an. Genau dieser Fall lief in `messenger_provider.dart` in ein
/// `catch (e) { if (kDebugMode) debugPrint(...); }`. Im Release-Build ist
/// `kDebugMode` false, der Fehler war also **vollständig unsichtbar**.
///
/// So konnte der Zustellbug ab Juni monatelang unentdeckt bleiben: die App
/// verhielt sich, als wäre alles in Ordnung. Ein abgelehnter Schreibvorgang
/// muss sichtbar werden, und er muss von einem Netzwerkfehler unterscheidbar
/// sein — `permission-denied` heißt praktisch immer, dass die Firestore-Rules
/// im Projekt älter sind als der Client.
void main() {
  group('einordnen', () {
    test('permission-denied ist eine Ablehnung, kein Netzwerkfehler', () {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      expect(KeyPublishStatus.classify(error), KeyPublishState.denied);
    });

    test('unavailable ist ein gewöhnlicher Fehlschlag', () {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      expect(KeyPublishStatus.classify(error), KeyPublishState.failed);
    });

    test('ein beliebiger Fehler ist ein gewöhnlicher Fehlschlag', () {
      expect(KeyPublishStatus.classify(Exception('kaputt')),
          KeyPublishState.failed);
    });
  });

  group('Gesamtzustand', () {
    late KeyPublishStatus status;

    setUp(() => status = KeyPublishStatus());

    test('startet gesund', () {
      expect(status.state, KeyPublishState.ok);
      expect(status.isHealthy, isTrue);
    });

    test('ein abgelehnter Identity-Key macht den Zustand ungesund', () {
      status.recordIdentityFailure(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ));
      expect(status.state, KeyPublishState.denied);
      expect(status.isHealthy, isFalse);
    });

    test('ein abgelehntes PreKey-Bundle zählt genauso', () {
      // Ohne Bundle kommt kein X3DH zustande — für die Zustellung ist das
      // genauso tödlich wie ein fehlender Identity-Key.
      status.recordPreKeyFailure(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ));
      expect(status.state, KeyPublishState.denied);
    });

    test('Ablehnung schlägt gewöhnlichen Fehlschlag', () {
      // Beide sind kaputt, aber nur die Ablehnung sagt einem, WO man suchen
      // muss. Die soll der Nutzer sehen.
      status.recordIdentityFailure(Exception('Netz weg'));
      status.recordPreKeyFailure(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ));
      expect(status.state, KeyPublishState.denied);
    });

    test('ein späterer Erfolg räumt den jeweiligen Fehler weg', () {
      status.recordIdentityFailure(Exception('Netz weg'));
      expect(status.state, KeyPublishState.failed);

      status.recordIdentitySuccess();
      expect(status.state, KeyPublishState.ok);
      expect(status.isHealthy, isTrue);
    });

    test('ein Erfolg auf der einen Seite überdeckt nicht die andere', () {
      // Der eigentliche Fallstrick: würde ein gelungener Identity-Key den
      // Gesamtzustand auf ok setzen, wäre ein abgelehntes Bundle wieder
      // unsichtbar — und damit wäre nichts gewonnen.
      status.recordPreKeyFailure(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ));
      status.recordIdentitySuccess();
      expect(status.state, KeyPublishState.denied);
    });

    test('erst wenn beide Seiten gelingen, ist der Zustand wieder gesund', () {
      status.recordIdentityFailure(Exception('a'));
      status.recordPreKeyFailure(Exception('b'));
      status.recordIdentitySuccess();
      expect(status.isHealthy, isFalse);
      status.recordPreKeySuccess();
      expect(status.isHealthy, isTrue);
    });
  });
}
