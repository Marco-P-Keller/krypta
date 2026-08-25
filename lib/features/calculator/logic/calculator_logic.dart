import 'package:flutter/foundation.dart';

/// Rechenlogik des Taschenrechners.
///
/// **Punkt vor Strich:** `2+3×4` ergibt 14, nicht 20. Gleichrangiges wird von
/// links nach rechts gerechnet, `100÷10÷2` ist also 5.
///
/// Gerechnet wird aus dem *getippten Text* heraus, nicht aus einem laufenden
/// Zwischenergebnis. Anders geht es nicht: solange `2+3` dasteht, ist noch
/// nicht entschieden, ob daraus 5 wird — ein folgendes `×` bindet die 3 an
/// den naechsten Operanden. Erst am Ende der Rechnung steht fest, was wozu
/// gehoert. Nebenbei faellt damit jedes Zwischenrunden weg.
///
/// Ketten: `5+5+5=` ergibt 15. Vorher ergab es 10 — `inputOperator` setzte
/// den ersten Operanden bedingungslos auf den Anzeigewert und warf die noch
/// offene Rechnung weg. Gefunden am 2026-08-24 beim Umbau der Anzeige.
class CalculatorLogic extends ChangeNotifier {
  /// Der Operand, der gerade getippt wird — bzw. das Ergebnis nach `=`.
  String _display = '0';

  /// Alles, was vor dem aktuellen Operanden steht, inklusive des offenen
  /// Operators: bei `5+5+` also genau `'5+5+'`. Hält den *getippten* Text
  /// fest, nicht die gerundete Zahl, damit `3.50+` nicht zu `3.5+` wird.
  String _chain = '';

  String _operator = '';
  bool _shouldResetDisplay = false;
  bool _hasDecimal = false;

  /// Die Rechnung, aus der der angezeigte Wert entstand, oder `null`, solange
  /// eingegeben wird. Steuert, ob die Anzeige einzeilig (Eingabe) oder
  /// zweizeilig (Ergebnis) rendert.
  String? _resultOf;

  /// Die getippte Ziffernfolge bzw. der aktuelle Operand — NICHT die
  /// angezeigte Rechenzeile. `CalculatorScreen._handleEquals` reicht genau
  /// das an den CodeDetector weiter; daran hängen Entsperren und
  /// Notfall-Löschung. Nicht auf [liveExpression] umstellen.
  String get display => _display;

  /// Was während der Eingabe gross dasteht: `5`, `5+`, `5+5`, `5+5+5`.
  /// Ohne Leerzeichen um den Operator.
  String get liveExpression {
    if (_chain.isEmpty) return _display;
    return _shouldResetDisplay ? _chain : '$_chain$_display';
  }

  /// Nach `=`: die Rechnung, die zum Ergebnis führte — sonst leer.
  String get completedExpression => _resultOf ?? '';

  /// Ob gerade ein Ergebnis gezeigt wird (zweizeilige Darstellung).
  bool get hasResult => _resultOf != null;

  void inputDigit(String digit) {
    _resultOf = null;
    if (_shouldResetDisplay) {
      _display = digit;
      _shouldResetDisplay = false;
      _hasDecimal = false;
    } else if (_display == '0' && digit != '.') {
      _display = digit;
    } else {
      if (_display.length >= 12) return;
      _display += digit;
    }
    notifyListeners();
  }

  void inputDecimal() {
    if (_hasDecimal) return;
    _resultOf = null;
    _hasDecimal = true;
    if (_shouldResetDisplay) {
      _display = '0.';
      _shouldResetDisplay = false;
    } else {
      _display += '.';
    }
    notifyListeners();
  }

  void inputOperator(String op) {
    _resultOf = null;

    if (_operator.isEmpty) {
      // Erster Operator der Kette. Steht dort 'Error', ist das keine Zahl —
      // dann faengt die Kette bei 0 an, statt den Fehler mitzuschleppen.
      final start = double.tryParse(_display) == null ? '0' : _display;
      _chain = '$start$op';
    } else if (_shouldResetDisplay) {
      // Operator direkt hintereinander gedrückt — den letzten ersetzen,
      // statt eine sinnlose Kette wie `5+×` entstehen zu lassen.
      _chain = _chain.substring(0, _chain.length - 1) + op;
    } else {
      // Der Operand ist fertig. Gerechnet wird erst am Ende, aber eine
      // Division durch null steht schon hier fest — und soll auch hier
      // auffallen, nicht erst beim Gleichheitszeichen.
      if (_evaluate('$_chain$_display') == null) {
        _failWithError();
        return;
      }
      _chain = '$_chain$_display$op';
    }

    _operator = op;
    _shouldResetDisplay = true;
    _hasDecimal = false;
    notifyListeners();
  }

  void calculate() {
    if (_operator.isEmpty) return;

    // Vor dem Zurücksetzen festhalten — danach steht sie klein und grau über
    // dem Ergebnis, statt wie bisher zu verschwinden.
    final completed = liveExpression;
    // Nicht liveExpression auswerten: nach `5+` steht dort nur `5+`. Der
    // Anzeigewert ist dann noch der erste Operand, `5+=` ergibt also 10 —
    // so verhaelt sich der Rechner seit jeher.
    final result = _evaluate('$_chain$_display');
    if (result == null) {
      _failWithError();
      return;
    }

    _display = _formatNumber(result);
    _resultOf = completed;
    _chain = '';
    _operator = '';
    _shouldResetDisplay = true;
    _hasDecimal = result != result.roundToDouble();
    notifyListeners();
  }

  /// Wertet die getippte Rechnung aus. `null` heisst: geht nicht — Division
  /// durch null oder ein Text, der keine Rechnung ist.
  ///
  /// Zwei Rangstufen genuegen, der Rechner kennt keine Klammern. Die Strich-
  /// Teile werden in [sum] aufsummiert, waehrend [term] den Punkt-Teil
  /// sammelt, der gerade laeuft; erst wenn ein `+` oder `−` kommt, ist der
  /// Term fertig und wandert in die Summe.
  ///
  /// Ein Minuszeichen ist entweder Vorzeichen oder Rechenoperator — hier
  /// lassen sich die beiden nicht verwechseln: [toggleSign] und
  /// [_formatNumber] schreiben ASCII `-`, die Taste liefert U+2212 `−`.
  static double? _evaluate(String expression) {
    double sum = 0;
    var addOp = '+';
    double term = 0;
    var mulOp = '';
    var i = 0;

    while (i < expression.length) {
      final start = i;
      if (expression[i] == '-') i++;
      while (i < expression.length && _isNumberChar(expression[i])) {
        i++;
      }
      final zahl = double.tryParse(expression.substring(start, i));
      if (zahl == null) return null;

      if (mulOp == '×') {
        term *= zahl;
      } else if (mulOp == '÷') {
        if (zahl == 0) return null;
        term /= zahl;
      } else {
        term = zahl;
      }
      mulOp = '';

      if (i >= expression.length) break;
      final op = expression[i];
      i++;
      if (op == '×' || op == '÷') {
        mulOp = op;
      } else if (op == '+' || op == '−') {
        sum = addOp == '+' ? sum + term : sum - term;
        addOp = op;
        term = 0;
      } else {
        return null;
      }
    }

    final ergebnis = addOp == '+' ? sum + term : sum - term;
    return ergebnis.isFinite ? ergebnis : null;
  }

  static bool _isNumberChar(String c) {
    if (c == '.') return true;
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  void _failWithError() {
    _display = 'Error';
    // Kein _resultOf: über 'Error' soll nicht die Rechnung stehen, als wäre
    // sie aufgegangen.
    _resultOf = null;
    _chain = '';
    _operator = '';
    _shouldResetDisplay = true;
    _hasDecimal = false;
    notifyListeners();
  }

  void clear() {
    _display = '0';
    _resultOf = null;
    _chain = '';
    _operator = '';
    _shouldResetDisplay = false;
    _hasDecimal = false;
    notifyListeners();
  }

  void toggleSign() {
    if (_display == '0') return;
    _resultOf = null;
    final value = double.tryParse(_display) ?? 0;
    _display = _formatNumber(-value);
    notifyListeners();
  }

  void percentage() {
    _resultOf = null;
    final value = double.tryParse(_display) ?? 0;
    _display = _formatNumber(value / 100);
    notifyListeners();
  }

  void backspace() {
    _resultOf = null;
    if (_display.length <= 1 || (_display.length == 2 && _display.startsWith('-'))) {
      _display = '0';
    } else {
      if (_display.endsWith('.')) _hasDecimal = false;
      _display = _display.substring(0, _display.length - 1);
    }
    notifyListeners();
  }

  /// Raw digit sequence for code detection (ignores operators/decimals).
  String get rawDigitSequence {
    return _display.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble() && !value.isInfinite && !value.isNaN) {
      return value.toInt().toString();
    }
    final formatted = value.toStringAsFixed(8);
    return formatted.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
