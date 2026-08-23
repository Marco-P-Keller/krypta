import 'package:flutter/foundation.dart';

/// Rechenlogik des Taschenrechners.
///
/// Rechnet **von links nach rechts**, ohne Punkt-vor-Strich — wie die
/// Rechner-App von iOS und wie diese Klasse es immer schon tat. `2+3×4`
/// ergibt hier also 20, nicht 14.
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

  /// Das Zwischenergebnis der Kette bis zum offenen Operator.
  double _accumulated = 0;

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
      // Erster Operator der Kette.
      _accumulated = double.tryParse(_display) ?? 0;
      _chain = '$_display$op';
    } else if (_shouldResetDisplay) {
      // Operator direkt hintereinander gedrückt — den letzten ersetzen,
      // statt eine sinnlose Kette wie `5+×` entstehen zu lassen.
      _chain = _chain.substring(0, _chain.length - 1) + op;
    } else {
      // Ein zweiter Operand steht da: die offene Rechnung jetzt ausführen,
      // sonst ginge sie verloren (das war der 5+5+5-Fehler).
      final next = _applyPending();
      if (next == null) {
        _failWithError();
        return;
      }
      _accumulated = next;
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
    final result = _applyPending();
    if (result == null) {
      _failWithError();
      return;
    }

    _display = _formatNumber(result);
    _resultOf = completed;
    _chain = '';
    _accumulated = 0;
    _operator = '';
    _shouldResetDisplay = true;
    _hasDecimal = result != result.roundToDouble();
    notifyListeners();
  }

  /// Führt den offenen Operator auf [_accumulated] und dem Anzeigewert aus.
  /// `null` bedeutet Division durch null.
  double? _applyPending() {
    final operand = double.tryParse(_display) ?? 0;
    switch (_operator) {
      case '+':
        return _accumulated + operand;
      case '−':
        return _accumulated - operand;
      case '×':
        return _accumulated * operand;
      case '÷':
        if (operand == 0) return null;
        return _accumulated / operand;
      default:
        return _accumulated;
    }
  }

  void _failWithError() {
    _display = 'Error';
    // Kein _resultOf: über 'Error' soll nicht die Rechnung stehen, als wäre
    // sie aufgegangen.
    _resultOf = null;
    _chain = '';
    _accumulated = 0;
    _operator = '';
    _shouldResetDisplay = true;
    _hasDecimal = false;
    notifyListeners();
  }

  void clear() {
    _display = '0';
    _resultOf = null;
    _chain = '';
    _accumulated = 0;
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
