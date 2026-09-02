import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/presentation/einmalige_nachricht_screen.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/message_bubble.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Was der Empfaenger von einer einmaligen Nachricht sieht, bevor er
/// bestaetigt hat: nichts vom Inhalt, nur die Schaltflaeche.
void main() {
  Message nachricht({required String von}) => Message(
        id: 'm1',
        chatId: 'c1',
        senderId: von,
        recipientId: von == 'ich' ? 'marco' : 'ich',
        encryptedContent: 'x',
        decryptedContent: 'GEHEIMER TEXT',
        timestamp: DateTime(2026, 9, 2, 14, 32),
        einmalig: true,
      );

  Future<void> zeige(WidgetTester t, Message m, {required bool isMine}) =>
      t.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: MessageBubble(message: m, isMine: isMine, onOeffnen: () {}),
        ),
      ));

  testWidgets('beim Empfaenger steht kein Inhalt, sondern Oeffnen', (t) async {
    await zeige(t, nachricht(von: 'marco'), isMine: false);
    // textContaining mit findRichText: der Text steckt in einem Text.rich,
    // und der WidgetSpan fuer die Uhrzeit haengt ein Ersatzzeichen an. Auf
    // Gleichheit zu pruefen waere scheinbar gruen, ohne etwas zu pruefen.
    expect(find.textContaining('GEHEIMER TEXT', findRichText: true),
        findsNothing,
        reason: 'der Inhalt darf vor dem Bestaetigen nirgends stehen');
    expect(find.text('Öffnen'), findsOneWidget);
  });

  testWidgets('beim Absender steht sein eigener Text', (t) async {
    await zeige(t, nachricht(von: 'ich'), isMine: true);
    expect(find.textContaining('GEHEIMER TEXT', findRichText: true),
        findsOneWidget);
    expect(find.text('Öffnen'), findsNothing);
  });

  // ─── Die eigene Ansicht ──────────────────────────────────────────────

  testWidgets('die Ansicht zeigt den Text und einen Schliessen-Knopf',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('de'),
      home: EinmaligeNachrichtScreen(text: 'GEHEIMER TEXT'),
    ));
    expect(find.text('GEHEIMER TEXT'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('ein langer Text scrollt, statt ueberzulaufen', (t) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(375, 667) * 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: EinmaligeNachrichtScreen(text: List.filled(80, 'Zeile').join(' ')),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
