import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/settings/presentation/sicherheitsdetails_screen.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Die Sicherheitsansicht, angelegt am 02.09.2026.
///
/// Sie richtet sich an Fachleute, wird also genau gelesen. Zwei Dinge muessen
/// deshalb halten: sie darf auf keinem Geraet ueberlaufen, und sie darf keine
/// Betriebsgroessen nennen, die nur jemandem helfen, der etwas kaputtmachen
/// will.
void main() {
  const sprachen = ['de', 'en', 'es', 'fr', 'it', 'nl', 'pt'];

  Future<void> zeige(
    WidgetTester t, {
    required String sprache,
    required Size geraet,
    required double schrift,
  }) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = geraet * 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      locale: Locale(sprache),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(schrift)),
        child: child!,
      ),
      home: const SicherheitsdetailsScreen(),
    ));
    await t.pumpAndSettle();
  }

  for (final sprache in sprachen) {
    testWidgets('sie baut ohne Ueberlauf, Sprache $sprache', (t) async {
      await zeige(t,
          sprache: sprache, geraet: const Size(375, 667), schrift: 1.0);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('kleinstes Geraet, maximale Schrift', (t) async {
    await zeige(t, sprache: 'de', geraet: const Size(375, 667), schrift: 1.35);
    expect(t.takeException(), isNull);
  });

  testWidgets('die acht Abschnitte sind da', (t) async {
    await zeige(t, sprache: 'de', geraet: const Size(390, 844), schrift: 1.0);
    final l10n = await AppLocalizations.delegate.load(const Locale('de'));
    for (final titel in [
      l10n.secMessagesTitle,
      l10n.secExchangeTitle,
      l10n.secForwardTitle,
      l10n.secIdentityTitle,
      l10n.secPasswordTitle,
      l10n.secLocalTitle,
      l10n.secServerTitle,
      l10n.secTransportTitle,
    ]) {
      // Scrollen, damit auch die unteren gebaut werden.
      await t.scrollUntilVisible(find.text(titel), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(titel), findsOneWidget);
    }
  });

  testWidgets('keine Betriebsgroessen, die einem Angreifer helfen', (t) async {
    // Fehlversuchsgrenzen, Token-Laufzeiten und die Obergrenze fuer
    // uebersprungene Nachrichten gehoeren nicht in eine oeffentliche Ansicht.
    // Sie nuetzen niemandem ausser jemandem, der etwas kaputtmachen will.
    // Verfahren und Parameter dagegen duerfen dastehen: sie geheim zu halten
    // waere Sicherheit durch Verschleierung.
    await zeige(t, sprache: 'de', geraet: const Size(390, 844), schrift: 1.0);
    final gefunden = t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join(' ')
        .toLowerCase();
    for (final verboten in [
      'fehlversuch',
      'maxskip',
      'minuten gültig',
      'notfall-löschung',
    ]) {
      expect(gefunden.contains(verboten), isFalse,
          reason: 'diese Angabe hilft nur einem Angreifer: $verboten');
    }
  });
}
