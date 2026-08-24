import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/core/locale/locale_controller.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Wacht darüber, dass die sieben Sprachen nicht auseinanderlaufen.
///
/// Der übliche Weg, wie so etwas kaputtgeht: jemand ergänzt einen Text in
/// `app_en.arb` und vergisst die anderen sechs Dateien. Beim Bauen fällt das
/// nicht auf — die generierte Klasse fällt still auf Englisch zurück, und der
/// Nutzer sieht mitten in seiner Sprache einen englischen Satz. Genau dieser
/// Mischmasch war der Grund, die Sprachauswahl überhaupt zu bauen.
///
/// Ebenso wichtig: Platzhalter. Wird aus `{timer}` in einer Übersetzung
/// versehentlich `{Timer}`, zeigt die App später wörtlich „{Timer}" an.
void main() {
  final dir = Directory('lib/l10n');

  Map<String, dynamic> readArb(String languageCode) {
    final file = File('${dir.path}/app_$languageCode.arb');
    expect(file.existsSync(), isTrue,
        reason: 'app_$languageCode.arb fehlt — jede unterstützte Sprache '
            'braucht eine Datei');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Platzhalter einer Zeichenkette: einfache `{name}` plus die Variable
  /// einer Pluralform `{name, plural, ...}`. Die Zweige einer Pluralform
  /// selbst zählen nicht mit.
  Set<String> placeholders(String text) {
    final simple = RegExp(r'\{(\w+)\}');
    final plural = RegExp(r'\{(\w+),\s*plural');
    return {
      ...simple.allMatches(text).map((m) => m.group(1)!),
      ...plural.allMatches(text).map((m) => m.group(1)!),
    };
  }

  late Map<String, dynamic> english;
  late List<String> englishKeys;

  setUpAll(() {
    english = readArb('en');
    englishKeys = english.keys.where((k) => !k.startsWith('@')).toList();
  });

  test('die Vorlage enthält überhaupt Texte', () {
    expect(englishKeys, isNotEmpty);
  });

  test('für jede angebotene Sprache gibt es eine Übersetzungsdatei', () {
    for (final locale in LocaleController.supported) {
      readArb(locale.languageCode);
    }
  });

  test('AppLocalizations kennt genau die angebotenen Sprachen', () {
    // Läuft das auseinander, lässt sich im Auswahl-Bildschirm eine Sprache
    // antippen, die Flutter danach gar nicht laden kann — die App bliebe
    // kommentarlos auf der alten Sprache stehen.
    final supported =
        LocaleController.supported.map((l) => l.languageCode).toSet();
    final known =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(known, supported);
  });

  for (final locale in LocaleController.supported) {
    final code = locale.languageCode;
    if (code == 'en') continue;

    group('app_$code.arb', () {
      test('hat genau dieselben Schlüssel wie die englische Vorlage', () {
        final arb = readArb(code);
        final keys = arb.keys.where((k) => !k.startsWith('@')).toSet();
        expect(keys.difference(englishKeys.toSet()), isEmpty,
            reason: 'Schlüssel, die es in app_en.arb nicht gibt');
        expect(englishKeys.toSet().difference(keys), isEmpty,
            reason: 'fehlende Übersetzungen — die App fiele hier still auf '
                'Englisch zurück');
      });

      test('keine leeren Übersetzungen', () {
        final arb = readArb(code);
        for (final key in englishKeys) {
          final value = arb[key];
          expect(value, isA<String>(), reason: '$key ist kein Text');
          expect((value as String).trim(), isNotEmpty,
              reason: '$key ist leer');
        }
      });

      test('Platzhalter stimmen mit der Vorlage überein', () {
        final arb = readArb(code);
        for (final key in englishKeys) {
          expect(
            placeholders(arb[key] as String),
            placeholders(english[key] as String),
            reason: '$key: die Platzhalter weichen von app_en.arb ab',
          );
        }
      });

      test('der Produktname bleibt unübersetzt', () {
        // „Krypta ECC" ist der Name im App Store. Wird der übersetzt, sucht
        // jemand die App unter einem Namen, den es dort nicht gibt.
        expect(readArb(code)['appName'], 'Krypta ECC');
      });
    });
  }
}
