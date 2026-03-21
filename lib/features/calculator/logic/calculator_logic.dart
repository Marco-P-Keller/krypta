import 'package:flutter/foundation.dart';

class CalculatorLogic extends ChangeNotifier {
  String _display = '0';
  String _expression = '';
  double _firstOperand = 0;
  String _operator = '';
  bool _shouldResetDisplay = false;
  bool _hasDecimal = false;

  String get display => _display;
  String get expression => _expression;

  void inputDigit(String digit) {
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
    _firstOperand = double.tryParse(_display) ?? 0;
    _operator = op;
    _expression = '${_formatNumber(_firstOperand)} $op';
    _shouldResetDisplay = true;
    _hasDecimal = false;
    notifyListeners();
  }

  void calculate() {
    if (_operator.isEmpty) return;
    final secondOperand = double.tryParse(_display) ?? 0;
    double result;

    switch (_operator) {
      case '+':
        result = _firstOperand + secondOperand;
      case '−':
        result = _firstOperand - secondOperand;
      case '×':
        result = _firstOperand * secondOperand;
      case '÷':
        if (secondOperand == 0) {
          _display = 'Error';
          _expression = '';
          _operator = '';
          notifyListeners();
          return;
        }
        result = _firstOperand / secondOperand;
      default:
        return;
    }

    _expression = '';
    _display = _formatNumber(result);
    _operator = '';
    _shouldResetDisplay = true;
    _hasDecimal = result != result.roundToDouble();
    notifyListeners();
  }

  void clear() {
    _display = '0';
    _expression = '';
    _firstOperand = 0;
    _operator = '';
    _shouldResetDisplay = false;
    _hasDecimal = false;
    notifyListeners();
  }

  void toggleSign() {
    if (_display == '0') return;
    final value = double.tryParse(_display) ?? 0;
    _display = _formatNumber(-value);
    notifyListeners();
  }

  void percentage() {
    final value = double.tryParse(_display) ?? 0;
    _display = _formatNumber(value / 100);
    notifyListeners();
  }

  void backspace() {
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
