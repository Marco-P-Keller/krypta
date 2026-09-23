import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/auth/presentation/lock_screen.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Der Sperrbildschirm, der ohne Taschenrechner davorsteht.
///
/// Zwei Dinge halten hier fest, was er ist und was er nicht ist.
void main() {
  Future<void> zeige(
    WidgetTester tester, {
    bool laeuft = false,
    VoidCallback? onUnlock,
  }) =>
      tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LockScreen(onUnlock: onUnlock ?? () {}, laeuft: laeuft),
      ));

  testWidgets('er sagt offen, dass die App gesperrt ist', (t) async {
    // Das ist der ganze Unterschied zum Rechner, dessen Sinn war, nicht wie
    // eine Sperre auszusehen. Wer ihn abschaltet, hat sich gegen die
    // Verkleidung entschieden, nicht gegen das Schloss.
    await zeige(t);
    final l10n = await AppLocalizations.delegate.load(const Locale('de'));
    expect(find.text(l10n.appName), findsOneWidget);
    expect(find.text(l10n.unlockAction), findsOneWidget);
  });

  testWidgets('er traegt keine Notfall-Loeschung', (t) async {
    // Vor dem Entsperren gibt es in dieser App keine Zerstoerung ohne
    // Wissen: am Rechner braucht sie den Loeschcode, am Tresor-Bildschirm
    // fuenf falsche Passwoerter. Ein Knopf haette jedem, der das gesperrte
    // Telefon in die Hand bekommt, mit zwei Tipps das Konto vernichtet —
    // samt der Meldung an alle Kontakte, dass es einen nicht mehr gibt.
    await zeige(t);
    final l10n = await AppLocalizations.delegate.load(const Locale('de'));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.text(l10n.emergencyDelete), findsNothing);
  });

  testWidgets('waehrend Face ID laeuft, ist der Knopf gesperrt', (t) async {
    var getippt = 0;
    await zeige(t, laeuft: true, onUnlock: () => getippt++);
    await t.tap(find.byType(FilledButton));
    await t.pump();
    expect(getippt, 0, reason: 'sonst stehen zwei Face-ID-Dialoge uebereinander');
  });

  testWidgets('sonst fuehrt er zum Entsperren', (t) async {
    var getippt = 0;
    await zeige(t, onUnlock: () => getippt++);
    await t.tap(find.byType(FilledButton));
    await t.pump();
    expect(getippt, 1);
  });
}
