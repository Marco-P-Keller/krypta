import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/einmalig_policy.dart';

/// Wann eine einmalige Nachricht verborgen wird und woran sie zu erkennen ist.
void main() {
  group('verbergen', () {
    test('beim Empfaenger wird verborgen', () {
      expect(
        EinmaligPolicy.verbergen(
            einmalig: true, senderId: 'marco', eigeneId: 'ich'),
        isTrue,
      );
    });

    test('beim Absender nicht: er sieht seinen eigenen Text', () {
      expect(
        EinmaligPolicy.verbergen(
            einmalig: true, senderId: 'ich', eigeneId: 'ich'),
        isFalse,
      );
    });

    test('eine gewoehnliche Nachricht wird nie verborgen', () {
      expect(
        EinmaligPolicy.verbergen(
            einmalig: false, senderId: 'marco', eigeneId: 'ich'),
        isFalse,
      );
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
