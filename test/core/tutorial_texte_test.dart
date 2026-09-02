import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Tutorialtexte in allen sieben Sprachen.
///
/// Der Anlass: Daniel hat das Tutorial am 02.09.2026 neu bestellt, „alles
/// kurz und buendig", und ausdruecklich gesagt, ich soll Bindestriche
/// vermeiden. Gemeint waren Gedankenstriche als Stilmittel, die ich sonst
/// staendig setze.
///
/// Eine Stilregel, die nur in einem Kommentar steht, haelt keine zwei
/// Aenderungen durch. Deshalb steht sie hier als Test.
void main() {
  const sprachen = ['de', 'en', 'es', 'fr', 'it', 'nl', 'pt'];

  Map<String, dynamic> arb(String code) => jsonDecode(
        File('lib/l10n/app_$code.arb').readAsStringSync(),
      ) as Map<String, dynamic>;

  Map<String, String> tutTexte(String code) {
    final d = arb(code);
    return {
      for (final e in d.entries)
        if (e.key.startsWith('tut') && e.value is String)
          e.key: e.value as String,
    };
  }

  test('alle sieben Sprachen tragen dieselben Tutorialtexte', () {
    final referenz = tutTexte('en').keys.toSet();
    expect(referenz, isNotEmpty);
    for (final code in sprachen) {
      expect(tutTexte(code).keys.toSet(), referenz,
          reason: 'app_$code.arb weicht bei den tut-Texten ab');
    }
  });

  for (final code in sprachen) {
    group('Sprache $code', () {
      test('kein Text ist leer', () {
        tutTexte(code).forEach((k, v) {
          expect(v.trim(), isNotEmpty, reason: '$k ist leer');
        });
      });

      test('keine Gedankenstriche', () {
        // Der Halbgeviertstrich und der Geviertstrich. Der gewoehnliche
        // Bindestrich in einem Wort wie QR-Code bleibt erlaubt, der traegt
        // Bedeutung.
        tutTexte(code).forEach((k, v) {
          expect(v.contains('—'), isFalse,
              reason: '$k enthaelt einen Geviertstrich: $v');
          expect(v.contains('–'), isFalse,
              reason: '$k enthaelt einen Halbgeviertstrich: $v');
        });
      });

      test('die Saetze bleiben kurz', () {
        // Nicht als Schoenheitsregel, sondern weil die Zeilen auf einer
        // Tutorialseite neben einem Symbol stehen und bei grosser
        // Systemschrift sonst die Seite sprengen.
        tutTexte(code).forEach((k, v) {
          expect(v.length, lessThanOrEqualTo(120),
              reason: '$k ist mit ${v.length} Zeichen zu lang: $v');
        });
      });
    });
  }
}
