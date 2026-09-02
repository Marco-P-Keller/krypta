import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/auth/presentation/tutorial_screen.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Ob die sechs Tutorialseiten auf jedem Geraet passen.
///
/// Der Anlass: das Tutorial wurde am 02.09.2026 von neun auf sechs Seiten
/// umgebaut, jede mit drei bis fuenf Zeilen. Dichter gepackte Seiten laufen
/// leichter ueber, besonders bei grosser Systemschrift und langen
/// Uebersetzungen.
void main() {
  Future<void> zeige(
    WidgetTester tester, {
    required Size geraet,
    required double schrift,
    required String sprache,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = geraet * 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: Locale(sprache),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(schrift)),
        child: child!,
      ),
      home: TutorialScreen(onComplete: () {}),
    ));
    await tester.pumpAndSettle();
  }

  /// Einmal durch alle Seiten wischen und jede einzeln pruefen.
  Future<void> durchblaettern(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      expect(tester.takeException(), isNull,
          reason: 'Seite ${i + 1} laeuft ueber');
      if (i < 5) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
      }
    }
  }

  testWidgets('sechs Punkte in der Leiste, nicht mehr neun', (t) async {
    await zeige(t,
        geraet: const Size(390, 844), schrift: 1.0, sprache: 'de');
    expect(find.byType(AnimatedContainer), findsNWidgets(6));
  });

  testWidgets('kleines Geraet, normale Schrift', (t) async {
    await zeige(t,
        geraet: const Size(375, 667), schrift: 1.0, sprache: 'de');
    await durchblaettern(t);
  });

  testWidgets('kleines Geraet, grosse Schrift', (t) async {
    await zeige(t,
        geraet: const Size(375, 667), schrift: 1.35, sprache: 'de');
    await durchblaettern(t);
  });

  // Franzoesisch und Portugiesisch tragen die laengsten Uebersetzungen.
  for (final sprache in const ['fr', 'pt']) {
    testWidgets('kleines Geraet, grosse Schrift, Sprache $sprache', (t) async {
      await zeige(t,
          geraet: const Size(375, 667), schrift: 1.35, sprache: sprache);
      await durchblaettern(t);
    });
  }

  testWidgets('die letzte Seite bietet den Einrichtungsknopf', (t) async {
    await zeige(t,
        geraet: const Size(390, 844), schrift: 1.0, sprache: 'de');
    final l10n = await AppLocalizations.delegate.load(const Locale('de'));
    for (var i = 0; i < 5; i++) {
      await t.drag(find.byType(PageView), const Offset(-400, 0));
      await t.pumpAndSettle();
    }
    expect(find.text(l10n.tutStartSetup), findsOneWidget);
  });
}
