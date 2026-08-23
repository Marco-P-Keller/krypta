import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';

class CalculatorKeypad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final void Function(String op) onOperator;
  final Future<void> Function() onEquals;
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
    const gap = 12.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      // Natürliche Höhe: die Tasten sind quadratisch (AspectRatio), das
      // Tastenfeld ist also so hoch, wie die fünf Reihen es brauchen. Der
      // Anzeigebereich darüber bekommt den Rest. Vorher lag hier ein fester
      // Flex-Anteil an, der grösser war als der Inhalt — der Überschuss fiel
      // unten weg und schob alles nach oben.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Row(gap: gap, children: [
            _Btn.fn('AC', onClear),
            _Btn.fn('±', onToggleSign),
            _Btn.fn('%', onPercentage),
            _Btn.op('÷', () => onOperator('÷')),
          ]),
          const SizedBox(height: 12),
          _Row(gap: gap, children: [
            _Btn.digit('7', () => onDigit('7')),
            _Btn.digit('8', () => onDigit('8')),
            _Btn.digit('9', () => onDigit('9')),
            _Btn.op('×', () => onOperator('×')),
          ]),
          const SizedBox(height: 12),
          _Row(gap: gap, children: [
            _Btn.digit('4', () => onDigit('4')),
            _Btn.digit('5', () => onDigit('5')),
            _Btn.digit('6', () => onDigit('6')),
            _Btn.op('−', () => onOperator('−')),
          ]),
          const SizedBox(height: 12),
          _Row(gap: gap, children: [
            _Btn.digit('1', () => onDigit('1')),
            _Btn.digit('2', () => onDigit('2')),
            _Btn.digit('3', () => onDigit('3')),
            _Btn.op('+', () => onOperator('+')),
          ]),
          const SizedBox(height: 12),
          _Row(gap: gap, children: [
            _Btn.zeroWide(() => onDigit('0')),
            _Btn.digit('.', onDecimal),
            _Btn.op('=', onEquals),
          ]),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  const _Row({required this.children, required this.gap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            flex: children[i] is _Btn && (children[i] as _Btn).wide ? 2 : 1,
            child: children[i],
          ),
        ],
      ],
    );
  }
}

enum _BtnType { digit, fn, op }

class _Btn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final _BtnType type;
  final bool wide;

  const _Btn._({
    required this.label,
    required this.onTap,
    required this.type,
    this.wide = false,
  });

  factory _Btn.digit(String l, VoidCallback t) =>
      _Btn._(label: l, onTap: t, type: _BtnType.digit);
  factory _Btn.fn(String l, VoidCallback t) =>
      _Btn._(label: l, onTap: t, type: _BtnType.fn);
  factory _Btn.op(String l, VoidCallback t) =>
      _Btn._(label: l, onTap: t, type: _BtnType.op);
  factory _Btn.zeroWide(VoidCallback t) =>
      _Btn._(label: '0', onTap: t, type: _BtnType.digit, wide: true);

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scale = Tween(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _bg {
    switch (widget.type) {
      case _BtnType.digit:
        return AppColors.calculatorButtonDark;
      case _BtnType.fn:
        return AppColors.calculatorButtonLight;
      case _BtnType.op:
        return AppColors.calculatorButtonAccent;
    }
  }

  Color get _fg {
    switch (widget.type) {
      case _BtnType.digit:
        return AppColors.calculatorDisplay;
      case _BtnType.fn:
        return Colors.black;
      case _BtnType.op:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AspectRatio(
          aspectRatio: widget.wide ? 2.18 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: _bg,
              shape: widget.wide ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: widget.wide ? BorderRadius.circular(100) : null,
            ),
            alignment: widget.wide ? Alignment.centerLeft : Alignment.center,
            padding: widget.wide ? const EdgeInsets.only(left: 32) : EdgeInsets.zero,
            // Fixed circular/pill bounds (AspectRatio above) can't grow with
            // the label the way a normal button can, so at the largest iOS
            // accessibility text sizes an unscaled glyph would clip against
            // them — scale the label down to fit, same as the display above.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                style: AppTypography.calculatorButton.copyWith(color: _fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
