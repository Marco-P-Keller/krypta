import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/unread_policy.dart';

/// Die zehn Faelle aus Daniels Liste vom 04.09.2026, der Reihe nach.
///
/// Gespielt wird der Weg, den auch der Provider geht, und zwar mit denselben
/// Regeln: bei der Zustellung entscheiden ([UnreadPolicy.beiZustellungGelesen]),
/// die Antwort als `readAt` an der Nachricht festschreiben, und den Zaehler
/// daraus **neu zaehlen** ([UnreadPolicy.zaehle]) statt ihn nebenher
/// hochzusetzen.
///
/// Genau diese Trennung war der Fehler: die Zustellung entschied anhand des
/// gerade offenen Chats und setzte einen Zaehler hoch, das Nachrechnen
/// entschied anhand von `readAt`. Der offene Chat wird nirgends gespeichert —
/// die beiden liefen auseinander, und was in der Liste stand, hing davon ab,
/// welche Stelle zuletzt gelaufen war.
///
/// Was diese Datei **nicht** prueft: die Verdrahtung im Provider. Der braucht
/// Firebase und laeuft nicht im Test; sie steht im Testprotokoll unter 10.8.
void main() {
  /// Ein Postfach, das den Weg des Providers nachspielt.
  ///
  /// Es kennt nur die drei Schritte, die auch dort passieren. Neuen Zustand
  /// gibt es hier bewusst nicht — sonst pruefte der Test seine eigene
  /// Erfindung.
  final ich = 'ich';

  ({
    void Function(String chatId, {String von, bool hinweis}) zustellen,
    void Function(String chatId) oeffnen,
    void Function() verlassen,
    void Function() weglegen,
    void Function() zurueckkommen,
    List<Message> Function(String chatId) neuGeladen,
    int Function(String chatId) badge,
    int Function(String chatId) punkte,
  }) postfach() {
    final chats = <String, List<Message>>{};
    String? offen;
    var vorne = true;
    var lauf = 0;

    void zustellen(String chatId, {String von = 'marco', bool hinweis = false}) {
      lauf++;
      final jetzt = DateTime(2026, 9, 4, 12, 0).add(Duration(minutes: lauf));
      final gelesen = UnreadPolicy.beiZustellungGelesen(
        senderId: von,
        eigeneId: ich,
        chatId: chatId,
        offenerChat: offen,
        imVordergrund: vorne,
      );
      chats.putIfAbsent(chatId, () => []).add(Message(
            id: 'm$lauf',
            chatId: chatId,
            senderId: von,
            recipientId: von == ich ? 'marco' : ich,
            encryptedContent: 'x',
            timestamp: jetzt,
            deliveredAt: jetzt,
            readAt: gelesen ? jetzt : null,
            status: gelesen ? MessageStatus.read : MessageStatus.delivered,
            systemEvent: hinweis ? SystemEventKind.screenshot : null,
          ));
    }

    /// Den Chat oeffnen heisst: alles darin als gelesen markieren.
    void oeffnen(String chatId) {
      offen = chatId;
      lauf++;
      final jetzt = DateTime(2026, 9, 4, 12, 0).add(Duration(minutes: lauf));
      final liste = chats[chatId] ?? [];
      for (var i = 0; i < liste.length; i++) {
        if (liste[i].senderId == ich || liste[i].readAt != null) continue;
        liste[i] = liste[i].copyWith(readAt: jetzt, status: MessageStatus.read);
      }
    }

    return (
      zustellen: zustellen,
      oeffnen: oeffnen,
      verlassen: () => offen = null,
      weglegen: () => vorne = false,
      zurueckkommen: () {
        vorne = true;
        if (offen != null) oeffnen(offen!);
      },
      // Der Neustart: was auf der Platte lag, kommt zurueck — mehr nicht.
      neuGeladen: (chatId) =>
          (chats[chatId] ?? []).map((m) => Message.fromMap(m.toMap())).toList(),
      badge: (chatId) =>
          UnreadPolicy.zaehle(chats[chatId] ?? const [], ich).anzahl,
      punkte: (chatId) =>
          UnreadPolicy.zaehle(chats[chatId] ?? const [], ich).hinweise,
    );
  }

  test('1. in der Chatliste: eine zugestellte Nachricht macht Badge 1', () {
    final p = postfach();
    p.zustellen('c1');
    expect(p.badge('c1'), 1);
  });

  test('2. eine zweite macht Badge 2, eine dritte Badge 3', () {
    final p = postfach();
    p.zustellen('c1');
    p.zustellen('c1');
    expect(p.badge('c1'), 2);
    p.zustellen('c1');
    expect(p.badge('c1'), 3);
  });

  test('3. Chat oeffnen: das Badge verschwindet ganz', () {
    final p = postfach();
    p.zustellen('c1');
    p.zustellen('c1');
    p.oeffnen('c1');
    expect(p.badge('c1'), 0);
  });

  test('4. in einem anderen Chat: das Badge erscheint beim richtigen', () {
    final p = postfach();
    p.oeffnen('c2');
    p.zustellen('c1');
    expect(p.badge('c1'), 1);
    expect(p.badge('c2'), 0);
  });

  test('5. im betroffenen Chat: kein Badge', () {
    final p = postfach();
    p.oeffnen('c1');
    p.zustellen('c1');
    expect(p.badge('c1'), 0);
  });

  test('6. und nach dem Verlassen bleibt es aus', () {
    final p = postfach();
    p.oeffnen('c1');
    p.zustellen('c1');
    p.verlassen();
    expect(p.badge('c1'), 0,
        reason: 'sie kam nicht ungelesen an — daran aendert das Verlassen '
            'nichts');
  });

  test('7. App weggelegt, Chat noch offen: das Badge kommt trotzdem', () {
    // Der Fall, der es verschluckt hat. Die Chat-Ansicht bleibt stehen, wenn
    // die App weggewischt wird — wer nicht hinsieht, hat nicht gelesen.
    final p = postfach();
    p.oeffnen('c1');
    p.weglegen();
    p.zustellen('c1');
    expect(p.badge('c1'), 1);

    // Und beim Zurueckkommen liegt der Chat wieder vor mir: gelesen.
    p.zurueckkommen();
    expect(p.badge('c1'), 0);
  });

  test('8. App geschlossen: nach dem Start steht der Zaehler richtig', () {
    final p = postfach();
    p.weglegen();
    p.zustellen('c1');
    p.zustellen('c1');
    // Neustart: gezaehlt wird, was von der Platte kommt.
    expect(UnreadPolicy.zaehle(p.neuGeladen('c1'), ich).anzahl, 2);
  });

  test('9. mehrere Chats zaehlen jeder fuer sich', () {
    final p = postfach();
    p.zustellen('c1');
    p.zustellen('c2');
    p.zustellen('c2');
    p.zustellen('c3', hinweis: true);
    expect(p.badge('c1'), 1);
    expect(p.badge('c2'), 2);
    expect(p.badge('c3'), 0, reason: 'ein Hinweis ist keine Nachricht');
    expect(p.punkte('c3'), 1, reason: 'er setzt aber den Punkt');

    p.oeffnen('c2');
    expect(p.badge('c2'), 0);
    expect(p.badge('c1'), 1, reason: 'der andere Chat bleibt unberuehrt');
  });

  test('10. Gelesenes kommt nach dem Neustart nie wieder als ungelesen', () {
    // Die Zusage haelt, weil `readAt` auf der Platte steht — und nicht, weil
    // irgendwo ein Zaehler auf null gesetzt wurde. Genau der Unterschied war
    // der Fehler: das Oeffnen setzte den Zaehler zurueck, liess die
    // Nachrichten aber ungelesen. Beim naechsten Nachrechnen stand das Badge
    // wieder da.
    final p = postfach();
    p.zustellen('c1');
    p.zustellen('c1');
    p.oeffnen('c1');
    p.verlassen();

    final nachNeustart = p.neuGeladen('c1');
    expect(UnreadPolicy.zaehle(nachNeustart, ich).anzahl, 0);
    expect(UnreadPolicy.zaehle(nachNeustart, ich).hinweise, 0);
    expect(UnreadPolicy.zaehle(nachNeustart, ich).ersteNeue, isNull);

    // Und eine neue Nachricht danach zaehlt wieder ganz normal.
    p.zustellen('c1');
    expect(p.badge('c1'), 1);
  });
}
