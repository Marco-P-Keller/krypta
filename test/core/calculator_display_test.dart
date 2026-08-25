import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/calculator/presentation/widgets/calculator_display.dart';

/// Auf dem Gerät gemeldet: die „0" stand mittig statt rechts.
///
/// Der Grund war nicht die Ausrichtung — die stand längst auf
/// `CrossAxisAlignment.end` — sondern die Breite. Ein `Column` ist nur so
/// breit wie sein breitestes Kind. Der Anzeigebereich war damit exakt so breit
/// wie die Ziffer, und der `Column` des Bildschirms darüber zentrierte ihn,
/// weil das seine Voreinstellung ist. Bei einer langen Rechnung fiel das nicht
/// auf, bei einer einzelnen Ziffer maximal.
///
/// Deshalb prüft dieser Test die tatsächliche Position auf dem Bildschirm und
/// nicht das Vorhandensein einer Eigenschaft: `crossAxisAlignment` war ja
/// korrekt gesetzt und die Anzeige trotzdem falsch.
void main() {
  const breite = 400.0;
  const seitenabstand = 24.0; // wie im Widget

  /// Baut die Anzeige so ein, wie der Rechner es tut: in einem `Column`, der
  /// seine Kinder zentriert, wenn sie ihn nicht ausfüllen.
  Future<void> zeige(
    WidgetTester tester, {
    required String wert,
    required String eingabe,
    String rechnung = '',
    bool ergebnis = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: breite,
            child: Column(
              children: [
                Expanded(
                  child: CalculatorDisplay(
                    displayValue: wert,
                    liveExpression: eingabe,
                    completedExpression: rechnung,
                    hasResult: ergebnis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Wie weit der rechte Rand des Textes vom rechten Rand des Bereichs weg ist.
  double abstandRechts(WidgetTester tester, String text) {
    final rect = tester.getRect(find.text(text));
    return breite - rect.right;
  }

  testWidgets('die einzelne Null steht rechts, nicht in der Mitte',
      (tester) async {
    await zeige(tester, wert: '0', eingabe: '');

    // Erlaubt ist der Seitenabstand plus ein Pixel Rundung. Stünde die Ziffer
    // mittig, waere der Abstand ungefaehr die halbe Breite.
    expect(abstandRechts(tester, '0'), lessThan(seitenabstand + 1));
  });

  testWidgets('eine kurze Eingabe steht ebenfalls rechts', (tester) async {
    await zeige(tester, wert: '7', eingabe: '7');
    expect(abstandRechts(tester, '7'), lessThan(seitenabstand + 1));
  });

  testWidgets('eine laufende Rechnung steht rechts', (tester) async {
    await zeige(tester, wert: '5', eingabe: '5+5+5');
    expect(abstandRechts(tester, '5+5+5'), lessThan(seitenabstand + 1));
  });

  testWidgets('bei einem Ergebnis stehen beide Zeilen rechts', (tester) async {
    await zeige(
      tester,
      wert: '15',
      eingabe: '',
      rechnung: '5+5+5',
      ergebnis: true,
    );
    expect(abstandRechts(tester, '15'), lessThan(seitenabstand + 1));
    expect(abstandRechts(tester, '5+5+5'), lessThan(seitenabstand + 1));
  });
}
