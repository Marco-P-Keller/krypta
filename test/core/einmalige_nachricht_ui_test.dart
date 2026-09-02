import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
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
}
