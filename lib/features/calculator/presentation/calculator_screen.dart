import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../logic/calculator_logic.dart';
import '../logic/code_detector.dart';
import '../../../services/emergency/emergency_wipe_service.dart';
import '../../messenger/logic/messenger_provider.dart';
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
    // Capture the wipe dependencies BEFORE the await: the emergency delete has
    // to run even when this State is disposed mid-verification, and reading
    // from context after dispose is illegal.
    final messenger = context.read<MessengerProvider>();
    final wipeService = context.read<EmergencyWipeService>();

    final result = await codeDetector.checkCode(_logic.display);
    // Argon2id verification takes a moment, and app.dart locks back to the
    // calculator on every lifecycle change — that disposes this State while
    // we await.
    final stillMounted = mounted;

    switch (result) {
      case CodeResult.delete:
        // Highest priority (delete outranks secret): an entered emergency wipe
        // must never be cancelled by lifecycle timing, so it runs regardless of
        // the mounted state. Only the UI parts are gated.
        if (stillMounted) _logic.clear();
        // Wipe in-memory messenger state first (ratchet keys, contacts, messages)
        await messenger.wipeAll();
        await wipeService.wipeEverything();
        if (mounted) widget.onDeleteCode();
        return;
      case CodeResult.secret:
        // A stale result must not notify a disposed logic and, worse, must not
        // hand out onSecretCode() right after an automatic lock.
        if (!stillMounted) return;
        _logic.clear();
        widget.onSecretCode();
        return;
      case CodeResult.none:
        if (!stillMounted) return;
        _logic.calculate();
    }
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
                // Der Anzeigebereich nimmt allen Platz über den Tasten und
                // richtet seinen Inhalt unten aus. Vorher stand hier ein
                // festes Verhältnis 2:4. Weil die Tasten quadratisch sind und
                // ihre zugeteilte Fläche nicht ausfüllten, blieb unten ein
                // Rest übrig, der ganze Block rutschte nach oben und die Zahl
                // stand optisch in der Mitte statt über den Tasten.
                Expanded(
                  child: CalculatorDisplay(
                    displayValue: _logic.display,
                    liveExpression: _logic.liveExpression,
                    completedExpression: _logic.completedExpression,
                    hasResult: _logic.hasResult,
                  ),
                ),
                CalculatorKeypad(
                  onDigit: _logic.inputDigit,
                  onOperator: _logic.inputOperator,
                  onEquals: _handleEquals,
                  onClear: _logic.clear,
                  onDecimal: _logic.inputDecimal,
                  onToggleSign: _logic.toggleSign,
                  onPercentage: _logic.percentage,
                  onBackspace: _logic.backspace,
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
