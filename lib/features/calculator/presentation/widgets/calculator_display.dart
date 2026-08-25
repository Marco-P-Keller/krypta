import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';

/// Der Anzeigebereich über dem Tastenfeld.
///
/// Zwei Zustände, bewusst getrennt:
///
/// * **Eingabe** — die laufende Rechnung steht gross und weiss da (`5`, `5+`,
///   `5+5`, `5+5+5`), darunter nichts. Vorher stand hier nur der zuletzt
///   getippte Operand, die Rechnung selbst klein darüber.
/// * **Ergebnis** — nach `=` rutscht die Rechnung klein und grau nach oben,
///   darunter erscheint das Ergebnis gross und weiss. Vorher verschwand die
///   Rechnung an dieser Stelle ganz.
///
/// Beides sitzt am unteren Rand, direkt über den Tasten. Dass es dort auch
/// wirklich landet, hängt am Tastenfeld: es nimmt seine natürliche Höhe ein,
/// damit dieser Bereich den ganzen Rest darüber füllt und
/// [MainAxisAlignment.end] etwas zu tun hat.
class CalculatorDisplay extends StatelessWidget {
  /// Der angezeigte Wert — bei einem Ergebnis dessen Zahl.
  final String displayValue;

  /// Die laufende Eingabe, z. B. `5+5+5`.
  final String liveExpression;

  /// Die Rechnung, die zum Ergebnis führte — nur bei [hasResult] gesetzt.
  final String completedExpression;

  /// Ob ein Ergebnis gezeigt wird (zweizeilig) oder eingegeben wird.
  final bool hasResult;

  const CalculatorDisplay({
    super.key,
    required this.displayValue,
    required this.liveExpression,
    required this.completedExpression,
    required this.hasResult,
  });

  @override
  Widget build(BuildContext context) {
    // Bei der Eingabe trägt die grosse Zeile die Rechnung selbst, bei einem
    // Ergebnis den Ergebniswert.
    final primary = hasResult
        ? (displayValue.isEmpty ? '0' : displayValue)
        : (liveExpression.isEmpty ? '0' : liveExpression);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      // Volle Breite erzwingen. Ohne das ist der Column nur so breit wie sein
      // breitestes Kind — bei einer einzelnen Ziffer also so breit wie die
      // Ziffer. `crossAxisAlignment: end` hat dann nichts auszurichten, und
      // der Column des Bildschirms darüber zentriert den ganzen Block, weil
      // das seine Voreinstellung ist. Ergebnis: die „0" stand mittig, eine
      // lange Rechnung dagegen richtig — sie füllte die Breite von selbst.
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (hasResult && completedExpression.isNotEmpty) ...[
              Text(
                completedExpression,
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
            ],
            // Lange Ketten dürfen nicht überlaufen — scaleDown verkleinert sie,
            // statt sie abzuschneiden.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                primary,
                style: AppTypography.calculatorDisplay.copyWith(
                  color: AppColors.calculatorDisplay,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
