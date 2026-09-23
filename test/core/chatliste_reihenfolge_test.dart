import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';
import 'package:kryptaapp/features/messenger/logic/chatliste_policy.dart';

/// In welcher Reihenfolge die Chats stehen.
///
/// Der Anlass: die Reihenfolge hing allein daran, dass `_touchChat` den Chat
/// an den Anfang der Liste schob. Bei einer ankommenden Nachricht stimmte
/// das auch. Es stimmte nur nicht bei den anderen Aufrufern derselben
/// Funktion: `deleteMessageForMe` und die Ablaufmeldung der Gegenseite rufen
/// sie, um die Uhrzeit auf die letzte **verbliebene** Nachricht
/// zurueckzusetzen. Ein Chat von vorletzter Woche sprang dadurch an die
/// Spitze, weil darin etwas geloescht wurde.
void main() {
  Chat chat(String id, DateTime? zeit) => Chat(
        id: id,
        recipientId: 'r_$id',
        recipientName: id,
        lastMessageTime: zeit,
      );

  test('die neueste Nachricht steht oben', () {
    final liste = [
      chat('alt', DateTime(2026, 9, 1)),
      chat('neu', DateTime(2026, 9, 22)),
      chat('mittel', DateTime(2026, 9, 10)),
    ];
    ChatOrder.sortiere(liste);
    expect(liste.map((c) => c.id), ['neu', 'mittel', 'alt']);
  });

  test('ein Chat ohne Nachricht steht unten, nicht oben', () {
    // Er ist frisch angelegt oder leergeraeumt und hat nichts zu zeigen —
    // aber er verdraengt keinen Verlauf.
    final liste = [
      chat('leer', null),
      chat('voll', DateTime(2026, 9, 22)),
    ];
    ChatOrder.sortiere(liste);
    expect(liste.map((c) => c.id), ['voll', 'leer']);
  });

  test('gleiche Uhrzeit heisst nicht zufaellige Reihenfolge', () {
    // Zwei Chats mit derselben Uhrzeit muessen bei jedem Aufbau gleich
    // stehen, sonst springt die Liste unter dem Finger.
    final zeit = DateTime(2026, 9, 22, 12);
    final a = [chat('b', zeit), chat('a', zeit)];
    final b = [chat('a', zeit), chat('b', zeit)];
    ChatOrder.sortiere(a);
    ChatOrder.sortiere(b);
    expect(a.map((c) => c.id), b.map((c) => c.id));
  });

  test('ein zurueckgesetzter Zeitstempel holt den Chat wieder herunter', () {
    // Genau der Fall aus dem Anlass: in einem alten Chat wird die letzte
    // Nachricht geloescht, seine Uhrzeit faellt auf die davor zurueck.
    final liste = [
      chat('gestern', DateTime(2026, 9, 21)),
      chat('alt', DateTime(2026, 9, 22, 18)),
    ];
    ChatOrder.sortiere(liste);
    expect(liste.first.id, 'alt');

    liste[liste.indexWhere((c) => c.id == 'alt')] =
        chat('alt', DateTime(2026, 8, 1));
    ChatOrder.sortiere(liste);
    expect(liste.first.id, 'gestern');
  });
}
