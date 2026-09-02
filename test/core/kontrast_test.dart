import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/theme/app_colors.dart';

/// Lesbarkeit der Textfarben im Dunkelmodus.
///
/// Der Anlass: eine externe Durchsicht am 02.09.2026 beanstandete die grauen
/// Beschreibungstexte. Nachgerechnet traf es die falsche Farbe —
/// [AppColors.textSecondaryDark] erfuellt die Anforderung, aber
/// [AppColors.textTertiaryDark] kam auf **1.86:1** und war damit weit davon
/// entfernt. Sie traegt keine Dekoration, sondern die Uhrzeiten und die
/// Restzeit unter einer Nachricht.
///
/// Gerechnet wird nach WCAG 2.1: relative Leuchtdichte, dann das
/// Kontrastverhaeltnis. AA verlangt 4.5:1 fuer gewoehnlichen Text.
void main() {
  double kanal(int c) {
    final v = c / 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
  }

  double leuchtdichte(Color c) =>
      0.2126 * kanal((c.r * 255).round()) +
      0.7152 * kanal((c.g * 255).round()) +
      0.0722 * kanal((c.b * 255).round());

  double kontrast(Color a, Color b) {
    final la = leuchtdichte(a), lb = leuchtdichte(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  const flaechen = {
    'schwarzer Grund': AppColors.backgroundDark,
    'Karte': AppColors.surfaceDark,
  };

  group('textTertiaryDark ist lesbar', () {
    for (final f in flaechen.entries) {
      test('auf ${f.key} mindestens 4.5:1', () {
        final k = kontrast(AppColors.textTertiaryDark, f.value);
        expect(k, greaterThanOrEqualTo(4.5),
            reason: 'nur ${k.toStringAsFixed(2)}:1 — die Uhrzeiten und die '
                'Restzeit unter der Blase stehen in dieser Farbe');
      });
    }
  });

  group('textSecondaryDark bleibt lesbar', () {
    for (final f in flaechen.entries) {
      test('auf ${f.key} mindestens 4.5:1', () {
        expect(kontrast(AppColors.textSecondaryDark, f.value),
            greaterThanOrEqualTo(4.5));
      });
    }
  });

  test('die Hierarchie stimmt: dritte Stufe zurueckhaltender als zweite', () {
    // Sonst stuende die unwichtigere Angabe staerker da als die wichtigere.
    expect(leuchtdichte(AppColors.textTertiaryDark),
        lessThan(leuchtdichte(AppColors.textSecondaryDark)),
        reason: 'textTertiaryDark muss dunkler bleiben als textSecondaryDark');
  });
}
