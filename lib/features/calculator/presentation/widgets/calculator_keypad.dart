import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';

class CalculatorKeypad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final void Function(String op) onOperator;
  final VoidCallback onEquals;
  final VoidCallback onClear;
  final VoidCallback onDecimal;
  final VoidCallback onToggleSign;
  final VoidCallback onPercentage;
  final VoidCallback onBackspace;

  const CalculatorKeypad({
    super.key,
    required this.onDigit,
    required this.onOperator,
    required this.onEquals,
    required this.onClear,
    required this.onDecimal,
    required this.onToggleSign,
    required this.onPercentage,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          _buildRow([
            _FunctionButton(label: 'AC', onTap: onClear),
            _FunctionButton(label: '±', onTap: onToggleSign),
            _FunctionButton(label: '%', onTap: onPercentage),
            _OperatorButton(label: '÷', onTap: () => onOperator('÷')),
          ]),
          const SizedBox(height: 10),
          _buildRow([
            _DigitButton(label: '7', onTap: () => onDigit('7')),
            _DigitButton(label: '8', onTap: () => onDigit('8')),
            _DigitButton(label: '9', onTap: () => onDigit('9')),
            _OperatorButton(label: '×', onTap: () => onOperator('×')),
          ]),
          const SizedBox(height: 10),
          _buildRow([
            _DigitButton(label: '4', onTap: () => onDigit('4')),
            _DigitButton(label: '5', onTap: () => onDigit('5')),
            _DigitButton(label: '6', onTap: () => onDigit('6')),
            _OperatorButton(label: '−', onTap: () => onOperator('−')),
          ]),
          const SizedBox(height: 10),
          _buildRow([
            _DigitButton(label: '1', onTap: () => onDigit('1')),
            _DigitButton(label: '2', onTap: () => onDigit('2')),
            _DigitButton(label: '3', onTap: () => onDigit('3')),
            _OperatorButton(label: '+', onTap: () => onOperator('+')),
          ]),
          const SizedBox(height: 10),
          _buildRow([
            _DigitButton(label: '0', flex: 2, onTap: () => onDigit('0')),
            _DigitButton(label: '.', onTap: onDecimal),
            _EqualsButton(onTap: onEquals),
          ]),
        ],
      ),
    );
  }

  Widget _buildRow(List<Widget> children) {
    return Row(
      children: children
          .expand((child) => [Expanded(flex: child is _DigitButton && child.flex > 1 ? child.flex : 1, child: child), const SizedBox(width: 10)])
          .toList()
        ..removeLast(),
    );
  }
}

class _DigitButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final int flex;

  const _DigitButton({required this.label, required this.onTap, this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return _CalcButton(
      label: label,
      backgroundColor: AppColors.calculatorButtonDark,
      textColor: AppColors.calculatorDisplay,
      onTap: onTap,
    );
  }
}

class _FunctionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FunctionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _CalcButton(
      label: label,
      backgroundColor: AppColors.calculatorButtonLight,
      textColor: Colors.black,
      onTap: onTap,
    );
  }
}

class _OperatorButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OperatorButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _CalcButton(
      label: label,
      backgroundColor: AppColors.calculatorButtonAccent,
      textColor: Colors.white,
      onTap: onTap,
    );
  }
}

class _EqualsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EqualsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _CalcButton(
      label: '=',
      backgroundColor: AppColors.calculatorButtonAccent,
      textColor: Colors.white,
      onTap: onTap,
    );
  }
}

class _CalcButton extends StatefulWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;

  const _CalcButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<_CalcButton> createState() => _CalcButtonState();
}

class _CalcButtonState extends State<_CalcButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AspectRatio(
          aspectRatio: widget.label == '0' ? 2.1 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(40),
            ),
            alignment: widget.label == '0'
                ? Alignment.centerLeft
                : Alignment.center,
            padding: widget.label == '0'
                ? const EdgeInsets.only(left: 28)
                : EdgeInsets.zero,
            child: Text(
              widget.label,
              style: AppTypography.calculatorButton.copyWith(
                color: widget.textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
