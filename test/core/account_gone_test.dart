import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/contact_model.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';

/// Was passiert, wenn jemand die Notfall-Löschung auslöst.
///
/// Die Gegenseite soll es erfahren: die Nachrichten dieser Person
/// verschwinden, im Verlauf steht ein Hinweis, und schreiben lässt sich
/// nicht mehr — das Konto gibt es nicht mehr, eine Nachricht dorthin käme
/// nie an.
void main() {
  group('Der Hinweis im Verlauf', () {
    test('ist eine eigene Art von Systemereignis', () {
      final m = Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: '',
        timestamp: DateTime(2026, 8, 25),
        systemEvent: SystemEventKind.accountDeleted,
      );

      expect(m.isSystemEvent, isTrue);
      expect(Message.fromMap(m.toMap()).systemEvent,
          SystemEventKind.accountDeleted);
    });

    test('eine unbekannte Art macht die Nachricht nicht kaputt', () {
      // Eine kuenftige Version koennte eine Art kennen, die diese nicht hat.
      // Ein Absturz hier waere teuer: loadMessages faengt Fehler ab und gibt
      // eine LEERE Liste zurueck — eine einzige unbekannte Nummer wuerde also
      // den ganzen Verlauf verschwinden lassen.
      final map = {
        'id': 'm2',
        'chatId': 'c1',
        'senderId': 'marco',
        'recipientId': 'ich',
        'encryptedContent': '',
        'timestamp': DateTime(2026, 8, 25).millisecondsSinceEpoch,
        'status': 0,
        'sysEvent': 99,
      };

      final m = Message.fromMap(map);

      expect(m.systemEvent, isNull);
      expect(m.id, 'm2');
    });
  });

  group('Der Kontakt gilt als fort', () {
    Contact kontakt({bool fort = false}) => Contact(
          id: 'marco',
          displayName: 'Marco',
          publicKey: Uint8List.fromList([1, 2, 3]),
          addedAt: DateTime(2026, 8, 1),
          isGone: fort,
        );

    test('normalerweise nicht', () {
      expect(kontakt().isGone, isFalse);
      expect(kontakt().canSendMessages, isTrue);
    });

    test('nach der Notfall-Loeschung schon — und dann kein Senden mehr', () {
      final fort = kontakt(fort: true);

      expect(fort.isGone, isTrue);
      expect(fort.canSendMessages, isFalse);
    });

    test('das ueberlebt den Neustart', () {
      final zurueck = Contact.fromMap(kontakt(fort: true).toMap());

      expect(zurueck.isGone, isTrue);
    });

    test('copyWith verliert es nicht', () {
      final kopie = kontakt(fort: true).copyWith(displayName: 'Marco K.');

      expect(kopie.isGone, isTrue);
    });

    test('und laesst sich setzen', () {
      expect(kontakt().copyWith(isGone: true).isGone, isTrue);
    });
  });
}
