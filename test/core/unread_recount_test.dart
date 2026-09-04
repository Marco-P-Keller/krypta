import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/unread_policy.dart';

/// Was in der Chatliste steht, nachdem Nachrichten verschwunden sind.
///
/// Der Anlass: der Zaehler und die Uhrzeit der ersten neuen Nachricht wurden
/// nur beim Eintreffen fortgeschrieben. Verschwanden Nachrichten danach — weil
/// ein Loeschtimer ablief oder die Gegenseite ihren Chat wegwarf —, blieben
/// beide stehen. In der Liste stand dann „3 neue" fuer einen Chat, in dem
/// nichts mehr liegt.
///
/// Statt nachzurechnen, was abgezogen werden muesste, wird schlicht neu
/// gezaehlt, was noch da ist. Das kann nicht auseinanderlaufen.
void main() {
  final frueh = DateTime(2026, 8, 31, 9, 0);
  final spaet = DateTime(2026, 8, 31, 17, 0);

  Message m({
    required String von,
    required DateTime zeit,
    DateTime? gelesen,
  }) =>
      Message(
        id: 'm-${zeit.hour}-$von',
        chatId: 'c1',
        senderId: von,
        recipientId: von == 'ich' ? 'marco' : 'ich',
        encryptedContent: 'x',
        timestamp: zeit,
        readAt: gelesen,
      );

  test('leerer Chat: nichts ungelesen, keine Uhrzeit', () {
    final z = UnreadPolicy.zaehle(const [], 'ich');
    expect(z.anzahl, 0);
    expect(z.ersteNeue, isNull);
  });

  test('nur eigene Nachrichten zaehlen nicht', () {
    final z = UnreadPolicy.zaehle([m(von: 'ich', zeit: frueh)], 'ich');
    expect(z.anzahl, 0);
    expect(z.ersteNeue, isNull);
  });

  test('gelesene Nachrichten zaehlen nicht', () {
    final z = UnreadPolicy.zaehle(
        [m(von: 'marco', zeit: frueh, gelesen: spaet)], 'ich');
    expect(z.anzahl, 0);
  });

  test('ungelesene der Gegenseite zaehlen, die Uhrzeit ist die frueheste', () {
    final z = UnreadPolicy.zaehle([
      m(von: 'marco', zeit: spaet),
      m(von: 'ich', zeit: spaet),
      m(von: 'marco', zeit: frueh),
      m(von: 'marco', zeit: frueh, gelesen: spaet),
    ], 'ich');

    expect(z.anzahl, 2);
    expect(z.ersteNeue, frueh, reason: 'die aelteste ungelesene gibt die Zeit');
  });

  test('verschwundene Nachrichten zaehlen nicht mehr mit', () {
    // Genau der Fehlerfall: vorher drei ungelesene, dann raeumt ein
    // Loeschtimer sie weg. Wird neu gezaehlt, steht in der Liste nichts mehr.
    final vorher = [
      m(von: 'marco', zeit: frueh),
      m(von: 'marco', zeit: spaet),
    ];
    expect(UnreadPolicy.zaehle(vorher, 'ich').anzahl, 2);
    expect(UnreadPolicy.zaehle(const [], 'ich').anzahl, 0);
    expect(UnreadPolicy.zaehle(const [], 'ich').ersteNeue, isNull);
  });

  // ─── Ab 02.09.2026: Hinweise zaehlen getrennt ────────────────────────
  //
  // Daniel: „es soll jede art von nachrichten und sobald sie angekommen sind
  // anzeigen." Ein Screenshot-Hinweis erschien in der Chatliste bisher
  // ueberhaupt nicht — kein Zaehler, keine Uhrzeit, der Chat rutschte nicht
  // einmal nach oben. Gleichzeitig zaehlte diese Funktion ihn sehr wohl mit,
  // sodass der Zaehler bei einer Neuberechnung rueckwirkend hochsprang.
  //
  // Jetzt getrennt: die Zahl gilt echten Nachrichten, der Punkt den
  // Hinweisen. Daniels Zusatz: passwortgeschuetzte Nachrichten und solche mit
  // eigenem Loeschtimer sind echte Nachrichten und gehoeren in die Zahl.

  Message hinweis({
    required String von,
    required DateTime zeit,
    DateTime? gelesen,
  }) =>
      Message(
        id: 'h-${zeit.hour}-$von',
        chatId: 'c1',
        senderId: von,
        recipientId: von == 'ich' ? 'marco' : 'ich',
        encryptedContent: '',
        timestamp: zeit,
        readAt: gelesen,
        systemEvent: SystemEventKind.screenshot,
      );

  test('ein Hinweis der Gegenseite zaehlt als Hinweis, nicht als Nachricht',
      () {
    final z = UnreadPolicy.zaehle([hinweis(von: 'marco', zeit: frueh)], 'ich');
    expect(z.anzahl, 0, reason: 'ein Screenshot ist keine Nachricht');
    expect(z.hinweise, 1);
    expect(z.ersteNeue, frueh, reason: 'seit wann etwas liegt, gilt trotzdem');
  });

  test('ein eigener Hinweis zaehlt gar nicht', () {
    // Meinen eigenen Screenshot muss mir die Chatliste nicht melden.
    final z = UnreadPolicy.zaehle([hinweis(von: 'ich', zeit: frueh)], 'ich');
    expect(z.anzahl, 0);
    expect(z.hinweise, 0);
    expect(z.ersteNeue, isNull);
  });

  test('ein gelesener Hinweis zaehlt nicht mehr', () {
    final z = UnreadPolicy.zaehle(
        [hinweis(von: 'marco', zeit: frueh, gelesen: spaet)], 'ich');
    expect(z.hinweise, 0);
  });

  test('eine passwortgeschuetzte Nachricht bleibt eine normale Nachricht', () {
    final z = UnreadPolicy.zaehle([
      Message(
        id: 'pw1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: 'x',
        timestamp: frueh,
        isPasswordProtected: true,
      ),
    ], 'ich');
    expect(z.anzahl, 1, reason: 'gehoert in die Zahl, nicht auf den Punkt');
    expect(z.hinweise, 0);
  });

  test('eine Nachricht mit eigenem Loeschtimer bleibt eine normale Nachricht',
      () {
    final z = UnreadPolicy.zaehle([
      Message(
        id: 'sd1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: 'x',
        timestamp: frueh,
        selfDestructDuration: const Duration(seconds: 30),
      ),
    ], 'ich');
    expect(z.anzahl, 1);
    expect(z.hinweise, 0);
  });

  test('die Uhrzeit ist das aelteste Ungelesene, gleich welcher Art', () {
    final z = UnreadPolicy.zaehle([
      m(von: 'marco', zeit: spaet),
      hinweis(von: 'marco', zeit: frueh),
    ], 'ich');
    expect(z.anzahl, 1);
    expect(z.hinweise, 1);
    expect(z.ersteNeue, frueh);
  });

  // ─── Wann ein Hinweis den Punkt in der Liste setzt ───────────────────
  //
  // Es gibt dafuer keine zweite Regel mehr. Der Hinweis geht denselben Weg
  // wie eine Nachricht: bei der Zustellung wird entschieden, ob er als
  // gesehen gilt, die Antwort steht als `readAt` an ihm, und gezaehlt wird
  // daraus. Frueher entschied hier `meldeHinweis` und dort `readAt` — zwei
  // Antworten auf dieselbe Frage.

  /// Der Punkt, wie ihn der Provider ermittelt: entscheiden, festschreiben,
  /// zaehlen.
  int punkte({required String von, String? offen, bool vorne = true}) {
    final gelesen = UnreadPolicy.beiZustellungGelesen(
      senderId: von,
      eigeneId: 'ich',
      chatId: 'c1',
      offenerChat: offen,
      imVordergrund: vorne,
    );
    return UnreadPolicy.zaehle(
      [hinweis(von: von, zeit: frueh, gelesen: gelesen ? frueh : null)],
      'ich',
    ).hinweise;
  }

  test('ein Hinweis der Gegenseite setzt den Punkt', () {
    expect(punkte(von: 'marco'), 1);
  });

  test('mein eigener Hinweis setzt keinen Punkt', () {
    expect(punkte(von: 'ich'), 0);
  });

  test('bei offenem Chat kein Punkt — man sieht den Hinweis ja', () {
    expect(punkte(von: 'marco', offen: 'c1'), 0);
  });

  test('ein anderer offener Chat schuetzt diesen hier nicht', () {
    expect(punkte(von: 'marco', offen: 'c2'), 1);
  });

  test('offen, aber die App liegt weg: der Punkt kommt', () {
    expect(punkte(von: 'marco', offen: 'c1', vorne: false), 1);
  });

  // ─── Ob eine Nachricht ueberhaupt ungelesen ankommt ──────────────────
  //
  // Der Kern des Fehlers vom 04.09.2026: „ungelesen" wurde an zwei Stellen
  // verschieden beantwortet. Beim Eintreffen entschied `_activeChatId` — ein
  // Wert, der nirgends gespeichert wird —, beim Nachrechnen `readAt` an der
  // Nachricht. Die beiden liefen auseinander, und der Zaehler sprang je
  // nachdem, welche Stelle zuletzt lief. Jetzt gibt es nur noch eine Frage,
  // und ihre Antwort steht an der Nachricht: `readAt`.
  group('Was bei der Zustellung schon als gelesen gilt', () {
    test('Fall 1: der Chat ist nicht offen — sie kommt ungelesen an', () {
      expect(
        UnreadPolicy.beiZustellungGelesen(
            senderId: 'marco',
            eigeneId: 'ich',
            chatId: 'c1',
            offenerChat: null,
            imVordergrund: true),
        isFalse,
      );
    });

    test('Fall 1b: ein anderer Chat ist offen — sie kommt ungelesen an', () {
      expect(
        UnreadPolicy.beiZustellungGelesen(
            senderId: 'marco',
            eigeneId: 'ich',
            chatId: 'c1',
            offenerChat: 'c2',
            imVordergrund: true),
        isFalse,
      );
    });

    test('Fall 2: der Chat liegt offen vor mir — sie gilt sofort als gelesen',
        () {
      // Sie steht in dem Moment auf dem Bildschirm. Sie hinterher als
      // ungelesen zu zaehlen waere schlicht falsch.
      expect(
        UnreadPolicy.beiZustellungGelesen(
            senderId: 'marco',
            eigeneId: 'ich',
            chatId: 'c1',
            offenerChat: 'c1',
            imVordergrund: true),
        isTrue,
      );
    });

    test('offen, aber die App liegt im Hintergrund — sie kommt ungelesen an',
        () {
      // Der Fall, der das Badge verschluckt hat: die Chat-Ansicht bleibt
      // stehen, wenn die App weggewischt wird, und `_activeChatId` mit ihr.
      // Wer nicht hinsieht, hat nicht gelesen.
      expect(
        UnreadPolicy.beiZustellungGelesen(
            senderId: 'marco',
            eigeneId: 'ich',
            chatId: 'c1',
            offenerChat: 'c1',
            imVordergrund: false),
        isFalse,
      );
    });

    test('meine eigene Nachricht zaehlt nie als ungelesen', () {
      expect(
        UnreadPolicy.beiZustellungGelesen(
            senderId: 'ich',
            eigeneId: 'ich',
            chatId: 'c1',
            offenerChat: null,
            imVordergrund: true),
        isTrue,
      );
    });

  });

  group('Ueber den Neustart hinweg', () {
    test('was im offenen Chat ankam, ist auch nach dem Laden gelesen', () {
      // Die Zusage: gelesene Nachrichten duerfen nach einem Neustart nie
      // wieder als ungelesen auftauchen. Sie haelt, weil `readAt` auf der
      // Platte steht — und nicht, weil irgendwo ein Zaehler auf null gesetzt
      // wurde.
      final zugestellt = m(von: 'marco', zeit: spaet, gelesen: spaet);
      final wieder = Message.fromMap(zugestellt.toMap());
      expect(wieder.readAt, spaet);
      expect(UnreadPolicy.zaehle([wieder], 'ich').anzahl, 0);
    });

    test('was ungelesen ankam, ist es nach dem Laden immer noch', () {
      final wieder = Message.fromMap(m(von: 'marco', zeit: spaet).toMap());
      expect(UnreadPolicy.zaehle([wieder], 'ich').anzahl, 1);
      expect(UnreadPolicy.zaehle([wieder], 'ich').ersteNeue, spaet);
    });
  });
}
