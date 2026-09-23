import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/nachrichtenregel.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';

/// Die vier Faelle aus Daniels Liste vom 22.09.2026, beim Senden.
///
///   1. Selbstlösch-Timer für den gesamten Chat.
///   2. Derselbe Timer für einzelne Nachrichten.
///   3. Nach Ansehen löschen.
///   4. Einmal ansehen.
///
/// Zwischen dem 02.09. und dem 22.09. gab es nur noch 1 und 4: die einmalige
/// Nachricht hatte den Einzeltimer und Burn after read abgeloest, jede
/// Nachricht ging mit `selfDestructFromChat: true` raus. Diese Datei haelt
/// fest, dass die vier wieder unterscheidbar sind — und vor allem, dass die
/// **Herkunft** der Frist stimmt. Daran haengt spaeter, welche Uhr gilt.
void main() {
  const fuenfMinuten = Duration(minutes: 5);
  const eineStunde = Duration(hours: 1);

  group('Was beim Senden mitgeht', () {
    test('ohne eigene Wahl gilt die Frist des Chats, und sie gilt als seine',
        () {
      final a = RegelPolicy.auftrag(
        regel: Nachrichtenregel.chatregel,
        chatFrist: fuenfMinuten,
      );
      expect(a.frist, fuenfMinuten);
      expect(a.vomChat, isTrue);
      expect(a.nachAnsehen, isFalse);
      expect(a.einmalig, isFalse);
    });

    test('eine eigene Frist gehoert der Nachricht, nicht dem Chat', () {
      final a = RegelPolicy.auftrag(
        regel: Nachrichtenregel.frist,
        einzelFrist: eineStunde,
        chatFrist: fuenfMinuten,
      );
      expect(a.frist, eineStunde);
      expect(a.vomChat, isFalse,
          reason: 'sonst folgt sie spaeter der Einstellung des Chats');
    });

    test('nach Ansehen loeschen traegt gar keine Uhr', () {
      final a = RegelPolicy.auftrag(
        regel: Nachrichtenregel.nachAnsehen,
        chatFrist: fuenfMinuten,
      );
      expect(a.frist, isNull);
      expect(a.nachAnsehen, isTrue);
      expect(a.einmalig, isFalse);
    });

    test('die einmalige Nachricht auch nicht', () {
      // Am 07.09.2026 erbte sie die Chat-Frist und war nach fuenf Minuten
      // fort, ungeoeffnet, auf beiden Geraeten.
      final a = RegelPolicy.auftrag(
        regel: Nachrichtenregel.einmalig,
        einzelFrist: eineStunde,
        chatFrist: fuenfMinuten,
      );
      expect(a.frist, isNull);
      expect(a.einmalig, isTrue);
      expect(a.nachAnsehen, isFalse,
          reason: 'zwei Zusagen an derselben Nachricht waeren eine zu viel');
    });

    test('eine Wahl ohne Dauer faellt auf den Chat zurueck, nicht ins Leere',
        () {
      final a = RegelPolicy.auftrag(
        regel: Nachrichtenregel.frist,
        chatFrist: fuenfMinuten,
      );
      expect(a.frist, fuenfMinuten);
      expect(a.vomChat, isTrue);
    });
  });

  group('Und was daraus spaeter folgt', () {
    Message nachricht(Sendeauftrag a) => Message(
          id: 'm1',
          chatId: 'c1',
          senderId: 'ich',
          recipientId: 'marco',
          encryptedContent: '',
          timestamp: DateTime(2026, 9, 22, 12),
          deliveredAt: DateTime(2026, 9, 22, 12),
          selfDestructDuration: a.frist,
          selfDestructFromChat: a.vomChat,
          burnAfterRead: a.nachAnsehen,
          einmalig: a.einmalig,
        );

    test('die eigene Frist bleibt, wenn der Chat umgestellt wird', () {
      final m = nachricht(RegelPolicy.auftrag(
        regel: Nachrichtenregel.frist,
        einzelFrist: eineStunde,
        chatFrist: fuenfMinuten,
      ));
      // Der Chat steht inzwischen auf sieben Tagen. Die Nachricht nicht.
      expect(
        SelfDestructPolicy.deadline(m, chatTimer: const Duration(days: 7)),
        DateTime(2026, 9, 22, 13),
      );
    });

    test('die Frist des Chats wandert mit seiner Einstellung', () {
      final m = nachricht(RegelPolicy.auftrag(
        regel: Nachrichtenregel.chatregel,
        chatFrist: fuenfMinuten,
      ));
      expect(
        SelfDestructPolicy.deadline(m, chatTimer: eineStunde),
        DateTime(2026, 9, 22, 13),
      );
    });

    test('nach Ansehen loeschen laeuft nie durch die Uhr ab', () {
      final m = nachricht(
          RegelPolicy.auftrag(regel: Nachrichtenregel.nachAnsehen));
      expect(SelfDestructPolicy.deadline(m), isNull);
      expect(
        SelfDestructPolicy.expired(m, DateTime(2027, 1, 1)),
        isFalse,
        reason: 'sie geht beim Verlassen des Chats, nicht nach Zeit',
      );
    });

    test('eine gelesene Nachricht mit nach Ansehen ist faellig', () {
      final a = RegelPolicy.auftrag(regel: Nachrichtenregel.nachAnsehen);
      final m = Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: '',
        timestamp: DateTime(2026, 9, 22, 12),
        deliveredAt: DateTime(2026, 9, 22, 12),
        readAt: DateTime(2026, 9, 22, 12, 1),
        burnAfterRead: a.nachAnsehen,
      );
      expect(m.shouldBurn, isTrue);
      expect(
        SelfDestructPolicy.announceBurn(m, 'ich'),
        isTrue,
        reason: 'der Absender erfaehrt davon, sonst bleibt sie bei ihm stehen',
      );
      expect(
        SelfDestructPolicy.acceptBurn(m, 'marco'),
        isTrue,
        reason: 'beim Absender darf seine eigene Nachricht damit weg',
      );
      expect(
        SelfDestructPolicy.acceptBurn(m, 'ich'),
        isFalse,
        reason: 'aber niemand raeumt mit einer Meldung fremde Nachrichten '
            'von meinem Geraet',
      );
    });
  });
}
