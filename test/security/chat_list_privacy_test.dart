import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/chat_tile.dart';

/// Was die Chatliste über den Inhalt verrät — und was nicht.
///
/// Bis hierher stand unter dem Namen der Klartext der letzten Nachricht.
/// Wer über die Schulter schaut oder das entsperrte Telefon in die Hand
/// bekommt, liest damit mit, ohne einen einzigen Chat zu öffnen. Der Ballon
/// mit der Zahl sagt dasselbe, was man wissen muss — dass etwas da ist —
/// ohne zu sagen, was.
Widget _rahmen(Chat chat) => MaterialApp(
      home: Scaffold(
        body: ChatTile(chat: chat, onTap: () {}),
      ),
    );

void main() {
  /// Ein Chat, wie ihn ein Bestandsgeraet liefert: [preview] steht noch in
  /// der gespeicherten Fassung, das Modell liest ihn nicht mehr.
  Chat chat({int unread = 0, String? preview}) => Chat.fromMap({
        'id': 'c1',
        'recipientId': 'r1',
        'recipientName': 'Marco',
        'lastMessagePreview': ?preview,
        'lastMessageTime': DateTime(2026, 8, 30, 14, 32).millisecondsSinceEpoch,
        'unreadCount': unread,
      });

  testWidgets('der Nachrichtentext steht nicht in der Liste', (tester) async {
    await tester.pumpWidget(_rahmen(chat(preview: 'hey bro')));

    expect(find.text('hey bro'), findsNothing,
        reason: 'die Liste ist von aussen lesbar, der Chat nicht');
    expect(find.text('Marco'), findsOneWidget);
  });

  testWidgets('auch ein alter gespeicherter Text taucht nicht auf',
      (tester) async {
    // Geraete, die schon laufen, haben den Klartext in chats.enc liegen.
    // Bis das Aufraeumen greift, darf die Kachel ihn trotzdem nicht zeigen.
    await tester.pumpWidget(_rahmen(chat(preview: 'Kontonummer DE12 3456')));

    expect(find.textContaining('Kontonummer'), findsNothing);
  });

  testWidgets('der Ballon zeigt die Zahl neuer Nachrichten', (tester) async {
    await tester.pumpWidget(_rahmen(chat(unread: 3)));

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('ohne neue Nachrichten kein Ballon', (tester) async {
    await tester.pumpWidget(_rahmen(chat()));

    expect(find.text('0'), findsNothing);
  });

  testWidgets('viele Nachrichten werden gedeckelt', (tester) async {
    // Die genaue Zahl ab hundert sagt mehr ueber die Nutzung aus, als sie
    // nuetzt — und sprengt den Kreis.
    await tester.pumpWidget(_rahmen(chat(unread: 143)));

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('143'), findsNothing);
  });
}
