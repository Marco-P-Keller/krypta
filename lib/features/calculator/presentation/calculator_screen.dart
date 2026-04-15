import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../logic/calculator_logic.dart';
import '../logic/code_detector.dart';
import '../../../services/emergency/emergency_wipe_service.dart';
import '../../../theme/app_colors.dart';
import 'widgets/calculator_display.dart';
import 'widgets/calculator_keypad.dart';

class CalculatorScreen extends StatefulWidget {
  final VoidCallback onSecretCode;
  final VoidCallback onDeleteCode;

  const CalculatorScreen({
    super.key,
    required this.onSecretCode,
    required this.onDeleteCode,
  });

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  late final CalculatorLogic _logic;

  @override
  void initState() {
    super.initState();
    _logic = CalculatorLogic();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _logic.dispose();
    super.dispose();
  }

  Future<void> _handleEquals() async {
    final codeDetector = context.read<CodeDetector>();
    final result = await codeDetector.checkCode(_logic.display);

    switch (result) {
      case CodeResult.secret:
        _logic.clear();
        widget.onSecretCode();
        return;
      case CodeResult.decoy:
        // Decoy mode removed — treat as no match
        break;
      case CodeResult.delete:
        _logic.clear();
        await _handleDeleteCode();
        return;
      case CodeResult.none:
        _logic.calculate();
    }
  }

  Future<void> _handleDeleteCode() async {
    final wipeService = context.read<EmergencyWipeService>();
    await wipeService.wipeEverything();
    if (mounted) widget.onDeleteCode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.calculatorBg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _logic,
          builder: (context, _) {
            return Column(
              children: [
                Expanded(
                  flex: 2,
                  child: CalculatorDisplay(
                    displayValue: _logic.display,
                    expression: _logic.expression,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: CalculatorKeypad(
                    onDigit: _logic.inputDigit,
                    onOperator: _logic.inputOperator,
                    onEquals: _handleEquals,
                    onClear: _logic.clear,
                    onDecimal: _logic.inputDecimal,
                    onToggleSign: _logic.toggleSign,
                    onPercentage: _logic.percentage,
                    onBackspace: _logic.backspace,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}
