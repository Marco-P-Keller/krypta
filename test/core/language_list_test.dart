import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/core/locale/locale_controller.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';
import 'package:kryptaapp/features/settings/presentation/language_screen.dart';
import 'package:provider/provider.dart';

/// Der einzige Widget-Test im Projekt, der tatsächlich etwas baut — der
/// bestehende „App smoke test" ist ein Platzhalter (`expect(1 + 1, 2)`).
///
/// Abgedeckt ist hier die Auswahlliste selbst: dass alle Sprachen erscheinen,
/// dass ein Tipp die Wahl übernimmt und dass die Markierung mitwandert. Der
/// Rest der Verdrahtung (MaterialApp.locale, der Eintrag in den
/// Einstellungen) braucht den vollen Provider-Baum und steht weiterhin unter
/// keinem Test.
void main() {
  ({LocaleController controller, Map<String, String> store}) build({
    String? stored,
  }) {
    final store = <String, String>{};
    if (stored != null) store['lang'] = stored;
    return (
      controller: LocaleController(
        read: () async => store['lang'],
        write: (value) async => store['lang'] = value,
      ),
      store: store,
    );
  }

  Widget wrap(LocaleController controller, {VoidCallback? onSelected}) {
    return ChangeNotifierProvider<LocaleController>.value(
      value: controller,
      child: MaterialApp(
        home: Scaffold(body: LanguageList(onSelected: onSelected)),
      ),
    );
  }

  testWidgets('zeigt jede Sprache in ihrer eigenen Schreibweise',
      (tester) async {
    final t = build();
    await tester.pumpWidget(wrap(t.controller));

    for (final locale in LocaleController.supported) {
      expect(find.text(LocaleController.labelFor(locale)), findsOneWidget);
    }
  });

  testWidgets('Englisch steht oben', (tester) async {
    final t = build();
    await tester.pumpWidget(wrap(t.controller));

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title as Text).data, 'English');
  });

  testWidgets('die aktuelle Sprache ist als einzige abgehakt', (tester) async {
    final t = build(stored: 'nl');
    await t.controller.load();
    await tester.pumpWidget(wrap(t.controller));

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    final checked = tester.widget<ListTile>(
      find.ancestor(
        of: find.byIcon(Icons.check_rounded),
        matching: find.byType(ListTile),
      ),
    );
    expect((checked.title as Text).data, 'Nederlands');
  });

  testWidgets('ein Tipp übernimmt die Sprache und merkt sie sich',
      (tester) async {
    final t = build();
    await tester.pumpWidget(wrap(t.controller));

    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(t.controller.locale, const Locale('fr'));
    expect(t.store['lang'], 'fr');
  });

  testWidgets('die Markierung wandert nach der Wahl mit', (tester) async {
    final t = build(stored: 'en');
    await t.controller.load();
    await tester.pumpWidget(wrap(t.controller));

    await tester.tap(find.text('Italiano'));
    await tester.pumpAndSettle();

    final checked = tester.widget<ListTile>(
      find.ancestor(
        of: find.byIcon(Icons.check_rounded),
        matching: find.byType(ListTile),
      ),
    );
    expect((checked.title as Text).data, 'Italiano');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('auch die letzte Sprache ist im Blatt erreichbar',
      (tester) async {
    // Auf dem Geraet gemeldet: in den Einstellungen liess sich Portugiesisch
    // nicht antippen. `showModalBottomSheet` deckelt die Hoehe ohne
    // `isScrollControlled` bei etwa der halben Bildschirmhoehe — sieben
    // Sprachen plus Ueberschrift passen da nicht hinein, der letzte Eintrag
    // lag ausserhalb.
    //
    // Deshalb ein kleines Geraet nachstellen und wirklich tippen: findsOne
    // allein wuerde den Fehler NICHT zeigen, denn gefunden wird der Eintrag
    // auch dann, wenn er ausserhalb liegt.
    tester.view.physicalSize = const Size(750, 1334); // iPhone SE, 2x
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final t = build();
    await tester.pumpWidget(
      ChangeNotifierProvider<LocaleController>.value(
        value: t.controller,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showLanguageSheet(context),
                child: const Text('oeffnen'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('oeffnen'));
    await tester.pumpAndSettle();

    final letzte = LocaleController.labelFor(LocaleController.supported.last);
    expect(find.text(letzte), findsOneWidget);

    // Der eigentliche Test: antippen. Liegt der Eintrag ausserhalb des
    // Blattes, schlaegt das hier fehl.
    await tester.tap(find.text(letzte));
    await tester.pumpAndSettle();

    expect(t.controller.locale, LocaleController.supported.last);
  });

  testWidgets('meldet die Wahl an den Aufrufer', (tester) async {
    // Beim Einrichten geht es danach weiter, in den Einstellungen schliesst
    // sich das Blatt. Ohne diesen Rückruf bliebe beides stehen.
    final t = build();
    var called = 0;
    await tester.pumpWidget(wrap(t.controller, onSelected: () => called++));

    await tester.tap(find.text('Português'));
    await tester.pumpAndSettle();

    expect(called, 1);
  });
}
