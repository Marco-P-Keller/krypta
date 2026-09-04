import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/control_message_policy.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';

/// Der Hinweis im Verlauf, wenn die Loeschdauer eines Chats geaendert wird.
///
/// Beide Seiten sollen ihn sehen, so wie die Hinweise auf Screenshots und
/// Aufnahmen. Dafuer muss die neue Dauer mitreisen — und Kontrollnachrichten
/// tragen nur eine Art und eine Kennung, sonst nichts.
///
/// Der Dauer ein eigenes Feld zu geben haette **jede** Signatur veraendert:
/// ein Geraet mit Build 97 wuerde danach auch Screenshot-Hinweise verwerfen.
/// Die Art ist ohnehin Teil der Signatur, also faelschungssicher — die Zahl
/// steht deshalb dort drin, und aeltere Fassungen ignorieren eine unbekannte
/// Art einfach.
void main() {
  group('Die Dauer reist in der Art mit', () {
    test('eine gesetzte Dauer', () {
      expect(
          SelfDestructPolicy.artFuerRegel(
              frist: const Duration(hours: 24), version: 0),
          'sdChanged:86400000:0');
    });

    test('ausgeschaltet', () {
      expect(SelfDestructPolicy.artFuerRegel(version: 0), 'sdChanged:off:0');
    });

    test('und wird wieder herausgelesen', () {
      expect(SelfDestructPolicy.regelAusArt('sdChanged:86400000:0')?.frist,
          const Duration(hours: 24));
      expect(SelfDestructPolicy.regelAusArt('sdChanged:300000:2')?.frist,
          const Duration(minutes: 5));
    });

    test('ausgeschaltet kommt als null zurueck', () {
      expect(SelfDestructPolicy.regelAusArt('sdChanged:off:0')?.frist, isNull);
    });

    test('eine fremde Art ist keine Fristaenderung', () {
      expect(SelfDestructPolicy.istChatFristAenderung('screenshot'), isFalse);
      expect(SelfDestructPolicy.istChatFristAenderung('sdChanged:off'), isTrue);
      expect(
          SelfDestructPolicy.istChatFristAenderung('sdChanged:1000'), isTrue);
    });

    test('Unsinn in der Zahl gilt als ausgeschaltet', () {
      // Fail-closed: lieber keine Frist als eine erfundene.
      expect(SelfDestructPolicy.regelAusArt('sdChanged:abc:0')?.frist, isNull);
      expect(SelfDestructPolicy.regelAusArt('sdChanged:-5:0')?.frist, isNull);
    });

    test('sie ueberlebt ein langes Offline', () {
      // Wie jede Zustandsaenderung: fuenf Minuten wuerden nicht reichen.
      expect(ControlMessagePolicy.maxAge('sdChanged:86400000'),
          ControlMessagePolicy.lang);
    });
  });

  group('Der Hinweis selbst laeuft nie ab', () {
    test('auch wenn er eine Dauer traegt', () {
      // Die Dauer steht am Hinweis, damit der Text sie nennen kann. Sie darf
      // ihn aber nicht selbst wegraeumen — ein Hinweis, der ausgerechnet dann
      // verschwindet, wenn man ihn braucht, waere sinnlos.
      final hinweis = Message(
        id: 'sys1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: '',
        timestamp: DateTime(2026, 8, 31, 12, 0),
        selfDestructDuration: const Duration(minutes: 5),
        systemEvent: SystemEventKind.selfDestructChanged,
      );

      expect(
        SelfDestructPolicy.expired(
            hinweis, DateTime(2026, 8, 31, 12, 0).add(const Duration(days: 30))),
        isFalse,
      );
    });
  });
}
