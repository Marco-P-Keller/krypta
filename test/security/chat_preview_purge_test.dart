import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';

/// Der Klartext der letzten Nachricht lag doppelt auf der Platte.
///
/// Er stand im Nachrichtenspeicher — und ein zweites Mal in `chats.enc`, als
/// `lastMessagePreview` der Chatliste. Verschlüsselt zwar, aber unter
/// demselben Schlüssel wie alles andere: zwei Kopien schützen nicht besser
/// als eine, sie vergrößern nur die Fläche.
///
/// Das Feld ist weg. Diese Tests halten fest, dass es auch nicht durch die
/// Hintertür zurückkommt — nicht beim Schreiben, und nicht beim Lesen eines
/// Bestands, der es noch enthält.
void main() {
  test('ein geschriebener Chat trägt keinen Nachrichtentext', () {
    final chat = Chat(
      id: 'c1',
      recipientId: 'r1',
      recipientName: 'Marco',
      lastMessageTime: DateTime(2026, 8, 30),
      unreadCount: 2,
    );

    expect(chat.toMap().containsKey('lastMessagePreview'), isFalse);
  });

  test('ein alter Bestand verliert den Text beim nächsten Schreiben', () {
    // Genau das liegt auf jedem Geraet, das die App schon hat.
    final alt = {
      'id': 'c1',
      'recipientId': 'r1',
      'recipientName': 'Marco',
      'lastMessagePreview': 'hey bro',
      'unreadCount': 2,
    };

    final geladen = Chat.fromMap(alt);
    final neu = geladen.toMap();

    expect(neu.containsKey('lastMessagePreview'), isFalse);
    expect(neu.values.whereType<String>(), isNot(contains('hey bro')));
    expect(geladen.unreadCount, 2,
        reason: 'der Zaehler ueberlebt, nur der Text faellt weg');
    expect(geladen.recipientName, 'Marco');
  });
}
