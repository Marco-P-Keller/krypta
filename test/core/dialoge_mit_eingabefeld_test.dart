import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Jeder Dialog mit einem Eingabefeld muss scrollen koennen.
///
/// Der Anlass: Daniel meldet aus Build 98, dass der Abbrechen-Knopf im
/// Sperren-Dialog auf dem Telefon seines Kollegen ueber dem Passwortfeld
/// liegt. AlertDialog kuerzt zu hohen Inhalt naemlich nicht, sondern malt ihn
/// ueber die Knopfzeile (dialog.dart: „let the content overflow").
///
/// Ein Eingabefeld ist dabei der gefaehrlichste Inhalt, weil es die Tastatur
/// hochholt und damit die Hoehe halbiert, die dem Dialog bleibt. Deshalb
/// diese Regel, und zwar am Quelltext statt am Bild: sie greift auch fuer
/// Dialoge, die es heute noch gar nicht gibt.
///
/// Der geometrische Nachweis, dass `scrollable` das gemeldete Bild wirklich
/// behebt, steht in passwort_dialog_layout_test.dart.
void main() {
  /// Der Klammerblock ab `AlertDialog(` bis zur passenden schliessenden
  /// Klammer. Zeichenketten und Kommentare werden uebersprungen, damit eine
  /// Klammer in einem Text die Zaehlung nicht verschiebt.
  String block(String quelle, int start) {
    var tiefe = 0;
    var i = start;
    while (i < quelle.length) {
      final c = quelle[i];
      if (c == "'" || c == '"') {
        final ende = c;
        i++;
        while (i < quelle.length) {
          if (quelle[i] == r'\') {
            i += 2;
            continue;
          }
          if (quelle[i] == ende) break;
          i++;
        }
      } else if (c == '/' && i + 1 < quelle.length && quelle[i + 1] == '/') {
        while (i < quelle.length && quelle[i] != '\n') {
          i++;
        }
      } else if (c == '(') {
        tiefe++;
      } else if (c == ')') {
        tiefe--;
        if (tiefe == 0) return quelle.substring(start, i + 1);
      }
      i++;
    }
    return quelle.substring(start);
  }

  test('AlertDialog mit Eingabefeld setzt scrollable', () {
    final suender = <String>[];

    for (final datei in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final quelle = datei.readAsStringSync();
      final zeilen = quelle.split('\n');

      for (final treffer in 'AlertDialog('.allMatches(quelle)) {
        final b = block(quelle, treffer.start);
        final hatFeld =
            b.contains('TextField(') || b.contains('TextFormField(');
        if (!hatFeld) continue;
        if (b.contains('scrollable:')) continue;
        // Ein Inhalt, der schon selbst scrollt, kann schrumpfen und sich
        // damit nicht ueber die Knoepfe legen. Der Titel bleibt dort
        // allerdings stehen — das genuegt, solange er kurz ist.
        if (b.contains('content: SingleChildScrollView') ||
            b.contains('content: ListView')) {
          continue;
        }

        final zeile =
            '\n'.allMatches(quelle.substring(0, treffer.start)).length + 1;
        suender.add('${datei.path}:$zeile  ->  '
            '${zeilen[zeile - 1].trim()}');
      }
    }

    expect(
      suender,
      isEmpty,
      reason: 'Diese Dialoge tragen ein Eingabefeld, koennen aber nicht '
          'scrollen — bei Tastatur und grosser Schrift legt sich ihr Inhalt '
          'ueber die Knopfzeile:\n  ${suender.join('\n  ')}\n',
    );
  });
}
