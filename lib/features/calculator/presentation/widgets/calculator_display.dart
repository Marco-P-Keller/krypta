import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';

class CalculatorDisplay extends StatelessWidget {
  final String displayValue;
  final String expression;

  const CalculatorDisplay({
    super.key,
    required this.displayValue,
    required this.expression,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (expression.isNotEmpty)
            Text(
              expression,
              style: const TextStyle(
                color: AppColors.textSecondaryDark,
                fontSize: 22,
                fontWeight: FontWeight.w300,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              displayValue.isEmpty ? '0' : displayValue,
              style: AppTypography.calculatorDisplay.copyWith(
                color: AppColors.calculatorDisplay,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
