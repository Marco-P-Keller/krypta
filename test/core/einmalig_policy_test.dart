import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/einmalig_policy.dart';

/// Wann eine einmalige Nachricht verborgen wird und woran sie zu erkennen ist.
void main() {
  group('verbergen', () {
    test('auf beiden Seiten, ohne nach der Seite zu fragen', () {
      // Daniels Entscheidung vom 04.09.2026: vorher las jeder, der dem
      // Absender ueber die Schulter sah, den Text ohne jedes Tor. Seitdem
      // nimmt `verbergen` keine Kennung mehr entgegen — die Signatur selbst
      // ist die Zusage. Was die Seiten unterscheidet, tragen `oeffenbar` und
      // `klartextBeimAbsender`, und beide sind unten geprueft.
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

    test('ohne bekannte eigene Kennung gibt es kein Tor', () {
      // Solange ich nicht weiss, wer ich bin, wird nichts geoeffnet. Die
      // Blase reicht die Kennung durch; fehlt sie, ist die sichere Antwort
      // „kein Tor" und nicht „Tor fuer jeden".
      expect(
        EinmaligPolicy.oeffenbar(
            einmalig: true, senderId: 'marco', eigeneId: null),
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

  group('nachzuraeumen', () {
    Message nachricht({
      required String von,
      required bool einmalig,
      String? klartext = 'GEHEIMER TEXT',
    }) =>
        Message(
          id: 'm1',
          chatId: 'c1',
          senderId: von,
          recipientId: von == 'ich' ? 'marco' : 'ich',
          encryptedContent: 'x',
          decryptedContent: klartext,
          timestamp: DateTime(2026, 9, 3, 12),
          einmalig: einmalig,
        );

    test('meine eigene einmalige Nachricht aus dem Bestand', () {
      // Alles, was ich zwischen dem 02.09. und dem 04.09.2026 einmalig
      // verschickt habe, liegt mit Klartext auf der Platte: damals wurde er
      // beim Senden noch behalten, und die Ablaufmeldung der Gegenseite
      // verwarf `acceptBurn`, weil `_vergaenglich` `einmalig` nicht kannte.
      // Die Blase zeigt seit dem 04.09. nichts mehr davon — das allein waere
      // die Kosmetik, vor der klartextBeimAbsender warnt.
      expect(
        EinmaligPolicy.nachzuraeumen(
            nachricht(von: 'ich', einmalig: true), 'ich'),
        isTrue,
      );
    });

    test('die Nachricht der Gegenseite bleibt: sie ist einmal zu oeffnen', () {
      expect(
        EinmaligPolicy.nachzuraeumen(
            nachricht(von: 'marco', einmalig: true), 'ich'),
        isFalse,
      );
    });

    test('meine gewoehnliche Nachricht behaelt ihren Text', () {
      expect(
        EinmaligPolicy.nachzuraeumen(
            nachricht(von: 'ich', einmalig: false), 'ich'),
        isFalse,
      );
    });

    test('ohne Klartext gibt es nichts nachzuraeumen', () {
      // Sonst schriebe der Start jedes Mal denselben Bestand neu.
      expect(
        EinmaligPolicy.nachzuraeumen(
            nachricht(von: 'ich', einmalig: true, klartext: null), 'ich'),
        isFalse,
      );
    });

    test('der ganze Bestand eines Chats auf einmal, und nur einmal', () {
      // Was `nachzuraeumen` je Nachricht entscheidet, muss der Aufrufer nur
      // noch speichern — und zwar nur, wenn sich wirklich etwas geaendert
      // hat. Sonst schriebe jeder Start jeden Chat neu.
      final bestand = [
        nachricht(von: 'ich', einmalig: true),
        nachricht(von: 'marco', einmalig: true),
        nachricht(von: 'ich', einmalig: false),
      ];

      expect(EinmaligPolicy.nachraeumen(bestand, 'ich'), isTrue);
      expect(bestand[0].decryptedContent, isNull);
      expect(bestand[1].decryptedContent, 'GEHEIMER TEXT',
          reason: 'die Gegenseite darf ihre Nachricht noch einmal oeffnen');
      expect(bestand[2].decryptedContent, 'GEHEIMER TEXT');
    });

    test('ein Chat ohne Bestand wird nicht neu geschrieben', () {
      final bestand = [
        nachricht(von: 'ich', einmalig: true, klartext: null),
        nachricht(von: 'marco', einmalig: false),
      ];

      expect(EinmaligPolicy.nachraeumen(bestand, 'ich'), isFalse);
      expect(bestand[1].decryptedContent, 'GEHEIMER TEXT');
    });

    test('ohne bekannte eigene Kennung wird nichts angetastet', () {
      // `userId` kann beim Start fehlen. Dann ist keine Nachricht als meine
      // zu erkennen, und eine leere Kennung darf nicht auf einen leeren
      // Absender passen.
      expect(
        EinmaligPolicy.nachzuraeumen(nachricht(von: '', einmalig: true), ''),
        isFalse,
      );
    });
  });
}
