import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';

/// Welche Uhrzeit in der Chatliste steht.
///
/// Der Anlass: dort stand die Uhrzeit der **letzten** Nachricht. Kamen mehrere
/// neue herein, wanderte sie mit — und der Zeitpunkt, an dem etwas Neues
/// anfing, war nicht mehr abzulesen. Solange etwas ungelesen ist, gehoert dort
/// die Uhrzeit der **ersten** ungelesenen Nachricht hin und bleibt stehen.
void main() {
  final morgens = DateTime(2026, 8, 31, 9, 15);
  final mittags = DateTime(2026, 8, 31, 12, 40);

  Chat chat({
    int ungelesen = 0,
    DateTime? ersteNeue,
    DateTime? letzte,
  }) =>
      Chat(
        id: 'c1',
        recipientId: 'marco',
        recipientName: 'Marco',
        lastMessageTime: letzte,
        firstUnreadAt: ersteNeue,
        unreadCount: ungelesen,
      );

  group('Angezeigte Uhrzeit', () {
    test('ohne Ungelesenes steht dort die letzte Nachricht', () {
      expect(chat(letzte: mittags).displayTime, mittags);
    });

    test('mit Ungelesenem steht dort die erste neue', () {
      // Genau der gemeldete Punkt: die Uhrzeit bleibt bei der ersten neuen
      // stehen, auch wenn danach weitere hereinkommen.
      expect(
        chat(ungelesen: 3, ersteNeue: morgens, letzte: mittags).displayTime,
        morgens,
      );
    });

    test('ohne vermerkte erste faellt sie auf die letzte zurueck', () {
      // Bestandsgeraete haben das Feld noch nicht. Lieber die alte Uhrzeit als
      // gar keine.
      expect(chat(ungelesen: 2, letzte: mittags).displayTime, mittags);
    });

    test('ganz ohne Nachrichten steht dort nichts', () {
      expect(chat().displayTime, isNull);
    });
  });

  group('Speichern und Laden', () {
    test('die erste neue ueberlebt den Rundlauf', () {
      final vorher = chat(ungelesen: 2, ersteNeue: morgens, letzte: mittags);
      expect(Chat.fromMap(vorher.toMap()).firstUnreadAt, morgens);
    });

    test('ein Bestandsdatensatz ohne das Feld bleibt heil', () {
      final alt = Chat.fromMap({
        'id': 'c1',
        'recipientId': 'marco',
        'recipientName': 'Marco',
        'lastMessageTime': mittags.millisecondsSinceEpoch,
        'unreadCount': 2,
      });

      expect(alt.firstUnreadAt, isNull);
      expect(alt.displayTime, mittags);
    });
  });
}
