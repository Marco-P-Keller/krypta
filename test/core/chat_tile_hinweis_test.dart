import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/chat_tile.dart';

/// Was die Chatliste rechts neben dem Namen zeigt.
///
/// Der Anlass: Daniel meldet am 02.09., die Anzeige ueberzeuge ihn nicht —
/// „es soll jede art von nachrichten und sobald sie angekommen sind
/// anzeigen." Ein Screenshot-Hinweis tauchte dort naemlich ueberhaupt nicht
/// auf.
///
/// Seine Entscheidung: die Zahl bleibt echten Nachrichten vorbehalten, ein
/// Hinweis bekommt einen eigenen Punkt. So ist von aussen unterscheidbar,
/// was einen erwartet.
void main() {
  Chat chat({int nachrichten = 0, int hinweise = 0}) => Chat(
        id: 'c1',
        recipientId: 'marco',
        recipientName: 'Marco',
        lastMessageTime: DateTime(2026, 9, 2, 14, 32),
        unreadCount: nachrichten,
        hinweisCount: hinweise,
      );

  Future<void> zeige(WidgetTester tester, Chat c) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatTile(chat: c, onTap: () {})),
        ),
      );

  /// Der Punkt traegt einen eigenen Schluessel: der Avatar links ist
  /// ebenfalls ein Kreis, ueber die Form allein waeren beide nicht zu
  /// trennen.
  Finder punkt() => find.byKey(const Key('hinweis-punkt'));

  testWidgets('nichts Neues: weder Punkt noch Zahl', (t) async {
    await zeige(t, chat());
    expect(punkt(), findsNothing);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('nur Nachrichten: die Zahl, kein Punkt', (t) async {
    await zeige(t, chat(nachrichten: 3));
    expect(find.text('3'), findsOneWidget);
    expect(punkt(), findsNothing);
  });

  testWidgets('nur ein Hinweis: der Punkt, keine Zahl', (t) async {
    await zeige(t, chat(hinweise: 1));
    expect(punkt(), findsOneWidget);
    expect(find.text('1'), findsNothing,
        reason: 'ein Screenshot ist keine Nachricht und traegt keine Zahl');
  });

  testWidgets('mehrere Hinweise bleiben ein einziger Punkt', (t) async {
    await zeige(t, chat(hinweise: 4));
    expect(punkt(), findsOneWidget);
    expect(find.text('4'), findsNothing);
  });

  testWidgets('beides zusammen: Punkt und Zahl stehen nebeneinander',
      (t) async {
    await zeige(t, chat(nachrichten: 2, hinweise: 1));
    expect(punkt(), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('ueber neunundneunzig steht 99+', (t) async {
    await zeige(t, chat(nachrichten: 120));
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('grosse Systemschrift schneidet nichts ab', (t) async {
    // Der Fall, in dem es eng wird: langer Name, dreistellige Zahl, Punkt
    // daneben — und dazu die groesste Schriftstufe.
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(375, 667) * 2.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: const TextScaler.linear(1.35),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: ChatTile(
          chat: Chat(
            id: 'c1',
            recipientId: 'marco',
            recipientName: 'Marco Maximilian von Habsburg-Lothringen',
            lastMessageTime: DateTime(2026, 9, 2, 14, 32),
            unreadCount: 128,
            hinweisCount: 2,
          ),
          onTap: () {},
        ),
      ),
    ));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull, reason: 'nichts darf ueberlaufen');
    expect(punkt(), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });
}
