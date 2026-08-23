import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/calculator/logic/calculator_logic.dart';

/// Die Rechenlogik hatte bis 2026-08-24 keinen einzigen Test — obwohl an
/// `display` die Code-Erkennung haengt und damit Entsperren und
/// Notfall-Loeschung. Diese Datei deckt beides ab: die neue Anzeigezeile und
/// die Zusicherungen, auf die sich CalculatorScreen und CodeDetector stuetzen.
void main() {
  late CalculatorLogic logic;

  setUp(() => logic = CalculatorLogic());
  tearDown(() => logic.dispose());

  group('Anzeigezeile waehrend der Eingabe', () {
    test('startet bei 0 und zeigt kein Ergebnis', () {
      expect(logic.liveExpression, '0');
      expect(logic.hasResult, isFalse);
    });

    test('waechst mit der Eingabe: 5 -> 5+ -> 5+5', () {
      logic.inputDigit('5');
      expect(logic.liveExpression, '5');

      logic.inputOperator('+');
      expect(logic.liveExpression, '5+');

      logic.inputDigit('5');
      expect(logic.liveExpression, '5+5');
    });

    test('kein Leerzeichen um den Operator', () {
      logic.inputDigit('1');
      logic.inputDigit('2');
      logic.inputOperator('×');
      logic.inputDigit('3');
      expect(logic.liveExpression, '12×3');
      expect(logic.liveExpression, isNot(contains(' ')));
    });

    test('waehrend der Eingabe steht nie ein Ergebnis bereit', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      expect(logic.hasResult, isFalse);
      expect(logic.completedExpression, isEmpty);
    });

    test('mehrstellige Operanden bleiben vollstaendig', () {
      for (final d in ['1', '2', '3']) {
        logic.inputDigit(d);
      }
      logic.inputOperator('−');
      for (final d in ['4', '5']) {
        logic.inputDigit(d);
      }
      expect(logic.liveExpression, '123−45');
    });

    test('Komma erscheint in der Zeile', () {
      logic.inputDigit('3');
      logic.inputDecimal();
      logic.inputDigit('5');
      expect(logic.liveExpression, '3.5');
    });
  });

  group('Nach dem Gleichheitszeichen', () {
    test('Rechnung bleibt stehen, Ergebnis kommt darunter', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.calculate();

      expect(logic.hasResult, isTrue);
      expect(logic.completedExpression, '5+5');
      expect(logic.display, '10');
    });

    test('die naechste Ziffer raeumt das Ergebnis weg', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.calculate();

      logic.inputDigit('7');
      expect(logic.hasResult, isFalse);
      expect(logic.completedExpression, isEmpty);
      expect(logic.liveExpression, '7');
    });

    test('weiterrechnen nimmt das Ergebnis als ersten Operanden', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.calculate();

      logic.inputOperator('×');
      expect(logic.hasResult, isFalse);
      expect(logic.liveExpression, '10×');

      logic.inputDigit('2');
      logic.calculate();
      expect(logic.completedExpression, '10×2');
      expect(logic.display, '20');
    });

    test('Division durch null zeigt Error und kein Ergebnis-Layout', () {
      logic.inputDigit('8');
      logic.inputOperator('÷');
      logic.inputDigit('0');
      logic.calculate();

      expect(logic.display, 'Error');
      // Kein hasResult: sonst stuende ueber "Error" noch die Rechnung, als
      // waere sie aufgegangen.
      expect(logic.hasResult, isFalse);
    });

    test('Vorzeichen und Prozent raeumen das Ergebnis ebenfalls weg', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.calculate();
      logic.toggleSign();
      expect(logic.hasResult, isFalse);

      logic.clear();
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.calculate();
      logic.percentage();
      expect(logic.hasResult, isFalse);
    });

    test('Ruecktaste raeumt das Ergebnis weg', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.calculate();
      logic.backspace();
      expect(logic.hasResult, isFalse);
    });

    test('AC setzt alles zurueck', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.calculate();
      logic.clear();

      expect(logic.hasResult, isFalse);
      expect(logic.completedExpression, isEmpty);
      expect(logic.liveExpression, '0');
      expect(logic.display, '0');
    });

    test('= ohne Operator aendert nichts', () {
      logic.inputDigit('7');
      logic.calculate();
      expect(logic.hasResult, isFalse);
      expect(logic.display, '7');
    });
  });

  group('Ketten', () {
    // Regression: 5+5+5 ergab vor dem 2026-08-24 genau 10. inputOperator setzte
    // den ersten Operanden bedingungslos auf den Anzeigewert und warf die noch
    // offene Rechnung weg. Ein Taschenrechner, der falsch rechnet, faellt auf —
    // fuer eine getarnte App ist das mehr als ein Schoenheitsfehler.
    test('5+5+5 ergibt 15', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.inputOperator('+');
      logic.inputDigit('5');
      logic.calculate();
      expect(logic.display, '15');
      expect(logic.completedExpression, '5+5+5');
    });

    test('die Zeile zeigt die ganze Kette', () {
      logic.inputDigit('5');
      logic.inputOperator('+');
      expect(logic.liveExpression, '5+');
      logic.inputDigit('5');
      expect(logic.liveExpression, '5+5');
      logic.inputOperator('+');
      expect(logic.liveExpression, '5+5+');
      logic.inputDigit('5');
      expect(logic.liveExpression, '5+5+5');
    });

    test('Zwischenergebnis stimmt bei gemischten Operatoren', () {
      // Von links nach rechts, kein Punkt-vor-Strich: (2+3)*4 = 20.
      logic.inputDigit('2');
      logic.inputOperator('+');
      logic.inputDigit('3');
      logic.inputOperator('×');
      logic.inputDigit('4');
      logic.calculate();
      expect(logic.display, '20');
      expect(logic.completedExpression, '2+3×4');
    });

    test('lange Kette', () {
      logic.inputDigit('1');
      for (var i = 0; i < 4; i++) {
        logic.inputOperator('+');
        logic.inputDigit('1');
      }
      logic.calculate();
      expect(logic.display, '5');
      expect(logic.completedExpression, '1+1+1+1+1');
    });

    test('Operator zweimal gedrueckt ersetzt ihn, statt die Kette zu verbiegen', () {
      logic.inputDigit('8');
      logic.inputOperator('+');
      logic.inputOperator('×');
      expect(logic.liveExpression, '8×');
      logic.inputDigit('2');
      logic.calculate();
      expect(logic.display, '16');
    });

    test('Division durch null mitten in der Kette bricht sauber ab', () {
      logic.inputDigit('8');
      logic.inputOperator('÷');
      logic.inputDigit('0');
      logic.inputOperator('+');
      expect(logic.display, 'Error');
      expect(logic.hasResult, isFalse);
    });

    test('nach Error setzt eine Ziffer neu auf', () {
      logic.inputDigit('8');
      logic.inputOperator('÷');
      logic.inputDigit('0');
      logic.calculate();
      expect(logic.display, 'Error');

      logic.inputDigit('3');
      expect(logic.display, '3');
      expect(logic.liveExpression, '3');
    });

    test('Kommazahlen behalten den getippten Text in der Kette', () {
      logic.inputDigit('1');
      logic.inputDecimal();
      logic.inputDigit('5');
      logic.inputOperator('+');
      expect(logic.liveExpression, '1.5+');
      logic.inputDigit('2');
      logic.calculate();
      expect(logic.display, '3.5');
      expect(logic.completedExpression, '1.5+2');
    });
  });

  group('Zusicherungen fuer die Code-Erkennung', () {
    // CalculatorScreen._handleEquals reicht `display` an CodeDetector weiter.
    // Wuerde dort die Anzeigezeile statt der getippten Ziffern landen, waere
    // der Geheimcode nicht mehr eingebbar und die Notfall-Loeschung tot.
    test('display bleibt die getippte Ziffernfolge, nicht die Rechenzeile', () {
      for (final d in ['1', '9', '8', '4']) {
        logic.inputDigit(d);
      }
      expect(logic.display, '1984');
      expect(logic.liveExpression, '1984');
    });

    test('display enthaelt nach einem Operator nur den zweiten Operanden', () {
      logic.inputDigit('1');
      logic.inputOperator('+');
      for (final d in ['2', '3', '4', '5']) {
        logic.inputDigit(d);
      }
      expect(logic.display, '2345');
      expect(logic.liveExpression, '1+2345');
    });

    test('rawDigitSequence filtert alles ausser Ziffern', () {
      logic.inputDigit('1');
      logic.inputDecimal();
      logic.inputDigit('2');
      expect(logic.rawDigitSequence, '12');
    });

    test('Eingabe ist auf 12 Zeichen begrenzt', () {
      for (var i = 0; i < 20; i++) {
        logic.inputDigit('9');
      }
      expect(logic.display.length, 12);
    });
  });
}
