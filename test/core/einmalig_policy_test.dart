import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/einmalig_policy.dart';

/// Wann eine einmalige Nachricht verborgen wird und woran sie zu erkennen ist.
void main() {
  group('verbergen', () {
    test('beim Empfaenger wird verborgen', () {
      expect(EinmaligPolicy.verbergen(einmalig: true), isTrue);
    });

    test('beim Absender ebenfalls: sein eigener Text steht nicht offen da', () {
      // Daniels Entscheidung vom 04.09.2026. Vorher las jeder, der dem
      // Absender ueber die Schulter sah, den Text ohne jedes Tor.
      expect(EinmaligPolicy.verbergen(einmalig: true), isTrue);
    });

    test('eine gewoehnliche Nachricht wird nie verborgen', () {
      expect(EinmaligPolicy.verbergen(einmalig: false), isFalse);
    });
  });

  group('oeffenbar', () {
    test('der Empfaenger darf oeffnen', () {
      expect(
        EinmaligPolicy.oeffenbar(
            einmalig: true, senderId: 'marco', eigeneId: 'ich'),
        isTrue,
      );
    });

    test('der Absender nicht: bei ihm gibt es nichts mehr zu oeffnen', () {
      expect(
        EinmaligPolicy.oeffenbar(
            einmalig: true, senderId: 'ich', eigeneId: 'ich'),
        isFalse,
      );
    });

    test('eine gewoehnliche Nachricht hat kein Tor', () {
      expect(
        EinmaligPolicy.oeffenbar(
            einmalig: false, senderId: 'marco', eigeneId: 'ich'),
        isFalse,
      );
    });
  });

  group('klartextBeimAbsender', () {
    test('eine einmalige Nachricht laesst beim Absender nichts zurueck', () {
      expect(EinmaligPolicy.klartextBeimAbsender(einmalig: true), isFalse);
    });

    test('eine gewoehnliche behaelt ihren Text', () {
      expect(EinmaligPolicy.klartextBeimAbsender(einmalig: false), isTrue);
    });
  });

  group('ausPayload', () {
    test('_once wird erkannt', () {
      expect(EinmaligPolicy.ausPayload({'_once': true}), isTrue);
    });

    test('ohne Feld ist die Nachricht gewoehnlich', () {
      expect(EinmaligPolicy.ausPayload({'text': 'hallo'}), isFalse);
    });

    test('_bar eines aelteren Absenders zaehlt NICHT als einmalig', () {
      // Der alte Absender hat Burn after read zugesagt, nicht Tor und
      // Bestaetigung. Sein Versprechen wird nicht nachtraeglich umgedeutet.
      expect(EinmaligPolicy.ausPayload({'_bar': true}), isFalse);
    });
  });
}
