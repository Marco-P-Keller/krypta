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

  testWidgets('beim Absender steht nur, dass er sie geschickt hat', (t) async {
    // Daniels Entscheidung vom 04.09.2026. Der Nachweis haengt hier bewusst
    // an einer Nachricht, die den Klartext noch traegt: die Blase darf ihn
    // auch dann nicht zeigen. Dass beim Senden gar nichts erst gespeichert
    // wird, ist die zweite Schranke — siehe EinmaligPolicy.
    await zeige(t, nachricht(von: 'ich'), isMine: true);
    expect(find.textContaining('GEHEIMER TEXT', findRichText: true),
        findsNothing,
        reason: 'der Absender sieht seinen eigenen Text nicht mehr');
    expect(find.text('Einmalige Nachricht gesendet'), findsOneWidget);
    // Kein Tor beim Absender: es gaebe nichts zu oeffnen.
    expect(find.text('Öffnen'), findsNothing);
    // Uhrzeit und Zustellstand bleiben. Er soll sehen, dass sie raus ist.
    expect(find.text('14:32'), findsOneWidget);
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

  // ─── Der Bestaetigungsdialog ─────────────────────────────────────────

  for (final sprache in const ['de', 'en', 'es', 'fr', 'it', 'nl', 'pt']) {
    testWidgets('der Bestaetigungsdialog passt, Sprache $sprache', (t) async {
      t.view.devicePixelRatio = 2.0;
      t.view.physicalSize = const Size(375, 667) * 2.0;
      addTearDown(t.view.reset);

      late AppLocalizations l10n;
      await t.pumpWidget(MaterialApp(
        locale: Locale(sprache),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: const TextScaler.linear(1.35)),
          child: child!,
        ),
        home: Builder(builder: (ctx) {
          l10n = AppLocalizations.of(ctx)!;
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    scrollable: true,
                    title: Row(
                      children: [
                        const Icon(Icons.visibility_off_rounded, size: 22),
                        const SizedBox(width: 10),
                        Expanded(child: Text(l10n.onceOnlyConfirmTitle)),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.onceOnlyConfirmBody),
                        const SizedBox(height: 12),
                        Text(l10n.onceOnlyScreenshotHint),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () {}, child: Text(l10n.cancel)),
                      FilledButton(
                          onPressed: () {},
                          child: Text(l10n.onceOnlyConfirmAction)),
                    ],
                  ),
                ),
                child: const Text('auf'),
              ),
            ),
          );
        }),
      ));
      await t.tap(find.text('auf'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull,
          reason: 'der Dialog laeuft in $sprache ueber');
    });
  }

  test('die Texte sind kurz und ohne Gedankenstriche', () async {
    // tutorial_texte_test deckt nur Schluessel ab, die mit tut beginnen.
    // Diese hier tun das nicht und waeren sonst ungeprueft.
    for (final sprache in const ['de', 'en', 'es', 'fr', 'it', 'nl', 'pt']) {
      final l = await AppLocalizations.delegate.load(Locale(sprache));
      final texte = <String, String>{
        'onceOnlyMessage': l.onceOnlyMessage,
        'openOnceMessage': l.openOnceMessage,
        'onceOnlyHiddenHint': l.onceOnlyHiddenHint,
        'onceOnlySentHint': l.onceOnlySentHint,
        'onceOnlyConfirmTitle': l.onceOnlyConfirmTitle,
        'onceOnlyConfirmBody': l.onceOnlyConfirmBody,
        'onceOnlyScreenshotHint': l.onceOnlyScreenshotHint,
        'onceOnlyConfirmAction': l.onceOnlyConfirmAction,
      };
      texte.forEach((k, v) {
        expect(v.trim(), isNotEmpty, reason: '$k ist leer in $sprache');
        expect(v.contains('—'), isFalse, reason: '$k in $sprache');
        expect(v.contains('–'), isFalse, reason: '$k in $sprache');
        expect(v.length, lessThanOrEqualTo(160), reason: '$k in $sprache');
      });
    }
  });
}
