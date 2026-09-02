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

  // ─── Wann ein Hinweis den Punkt setzt ────────────────────────────────

  test('ein Hinweis der Gegenseite setzt den Punkt', () {
    expect(
      UnreadPolicy.meldeHinweis(
          senderId: 'marco',
          eigeneId: 'ich',
          chatId: 'c1',
          offenerChat: null),
      isTrue,
    );
  });

  test('mein eigener Hinweis setzt keinen Punkt', () {
    expect(
      UnreadPolicy.meldeHinweis(
          senderId: 'ich', eigeneId: 'ich', chatId: 'c1', offenerChat: null),
      isFalse,
    );
  });

  test('bei offenem Chat kein Punkt — man sieht den Hinweis ja', () {
    expect(
      UnreadPolicy.meldeHinweis(
          senderId: 'marco',
          eigeneId: 'ich',
          chatId: 'c1',
          offenerChat: 'c1'),
      isFalse,
    );
  });

  test('ein anderer offener Chat schuetzt diesen hier nicht', () {
    expect(
      UnreadPolicy.meldeHinweis(
          senderId: 'marco',
          eigeneId: 'ich',
          chatId: 'c1',
          offenerChat: 'c2'),
      isTrue,
    );
  });
}
