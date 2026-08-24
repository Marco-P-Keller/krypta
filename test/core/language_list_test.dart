import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/core/locale/locale_controller.dart';
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
