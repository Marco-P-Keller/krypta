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
}
