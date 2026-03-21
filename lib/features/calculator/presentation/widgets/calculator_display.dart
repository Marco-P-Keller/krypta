import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';

class CalculatorDisplay extends StatelessWidget {
  final String displayValue;
  final String expression;

  const CalculatorDisplay({
    super.key,
    required this.displayValue,
    this.expression = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (expression.isNotEmpty)
            Text(
              expression,
              style: AppTypography.textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondaryDark,
                fontSize: 20,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
            ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              displayValue,
              style: AppTypography.calculatorDisplay.copyWith(
                color: AppColors.calculatorDisplay,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
