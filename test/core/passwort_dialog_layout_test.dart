import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/passwort_dialog.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Ob die beiden Passwortdialoge auf jedem Geraet passen.
///
/// Der Anlass: Daniel meldet aus Build 98, dass auf dem Telefon seines
/// Kollegen der Abbrechen-Knopf im Sperren-Dialog ueber dem Passwortfeld
/// liegt, waehrend bei ihm selbst alles sitzt. AlertDialog kuerzt zu hohen
/// Inhalt naemlich nicht, sondern malt ihn ueber die Knopfzeile.
///
/// Gemessen wird deshalb genau das gemeldete Bild: die Knopfzeile darf das
/// Passwortfeld nicht beruehren, und nichts darf ueberlaufen. Die Testschrift
/// ist breiter als jede echte (jedes Zeichen ein volles Geviert), die Faelle
/// hier sind also strenger als das Geraet des Kollegen.
void main() {
  const geraete = <String, Size>{
    'iPhone SE': Size(375, 667),
    'iPhone 13 mini': Size(375, 812),
    'iPhone 15 Pro Max': Size(430, 932),
  };

  Future<void> zeige(
    WidgetTester tester, {
    required Size geraet,
    required double tastatur,
    required double schrift,
    required Locale sprache,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = geraet * 2.0;
    addTearDown(tester.view.reset);

    late AppLocalizations l10n;
    await tester.pumpWidget(MaterialApp(
      locale: sprache,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          viewInsets: EdgeInsets.only(bottom: tastatur),
          textScaler: TextScaler.linear(schrift),
        ),
        child: child!,
      ),
      home: Builder(builder: (ctx) {
        l10n = AppLocalizations.of(ctx)!;
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog(
                context: ctx,
                builder: (d) => PasswortDialog(
                  symbol: Icons.lock_rounded,
                  symbolFarbe: Colors.orange,
                  symbolGroesse: 22,
                  titel: l10n.lockMessage,
                  hinweis: l10n.lockMessageHint,
                  feld: TextField(
                    autofocus: true,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: l10n.enterPassword,
                      prefixIcon: const Icon(Icons.key_rounded, size: 20),
                    ),
                  ),
                  aktionen: [
                    TextButton(
                        onPressed: () {}, child: Text(l10n.cancel)),
                    ElevatedButton(
                        onPressed: () {}, child: Text(l10n.setPassword)),
                  ],
                ),
              ),
              child: const Text('auf'),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
  }

  /// Daniels Meldung, in eine Zusicherung uebersetzt.
  void knoepfeLiegenNichtAufDemFeld(WidgetTester tester) {
    final feld = tester.getRect(find.byType(TextField));
    for (final knopf in <Finder>[
      find.byType(TextButton),
      find.byType(ElevatedButton).last,
    ]) {
      final r = tester.getRect(knopf);
      expect(r.overlaps(feld), isFalse,
          reason: 'Knopf $r liegt auf dem Passwortfeld $feld');
    }
  }

  void allesAufDemSchirm(WidgetTester tester, Size geraet) {
    final r = tester.getRect(find.byType(TextButton));
    expect(r.bottom, lessThanOrEqualTo(geraet.height),
        reason: 'Abbrechen ragt unten aus dem Bildschirm');
    expect(r.top, greaterThanOrEqualTo(0.0),
        reason: 'Abbrechen ragt oben aus dem Bildschirm');
  }

  for (final eintrag in geraete.entries) {
    for (final tastatur in <double>[0, 300]) {
      for (final schrift in <double>[1.0, 1.35]) {
        testWidgets(
            '${eintrag.key}, Tastatur $tastatur, Schrift $schrift',
            (t) async {
          await zeige(t,
              geraet: eintrag.value,
              tastatur: tastatur,
              schrift: schrift,
              sprache: const Locale('de'));
          expect(t.takeException(), isNull);
          knoepfeLiegenNichtAufDemFeld(t);
          allesAufDemSchirm(t, eintrag.value);
        });
      }
    }
  }

  // Die laengsten Titel stehen im Franzoesischen und im Portugiesischen.
  for (final sprache in const ['de', 'en', 'es', 'fr', 'it', 'nl', 'pt']) {
    testWidgets('kleinstes Geraet, grosse Schrift, Sprache $sprache',
        (t) async {
      await zeige(t,
          geraet: const Size(375, 667),
          tastatur: 300,
          schrift: 1.35,
          sprache: Locale(sprache));
      expect(t.takeException(), isNull);
      knoepfeLiegenNichtAufDemFeld(t);
    });
  }
}
