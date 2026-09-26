import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/theme/app_colors.dart';

/// Die Farbe hinter dem Anfangsbuchstaben eines Kontakts.
///
/// Stand bis 25.09.2026 dreimal im Code, in zwei Fassungen: Sarah war in der
/// Chatliste blau und im Chat gruen. Jetzt gibt es sie nur noch einmal.
void main() {
  test('derselbe Name bekommt immer denselben Verlauf', () {
    expect(AppColors.avatarGradientFor('Sarah'),
        same(AppColors.avatarGradientFor('Sarah')));
  });

  test('ein leerer Name faellt nicht um', () {
    expect(AppColors.avatarGradientFor(''), AppColors.avatarGradients.first);
  });

  test('jeder Verlauf hat zwei Farben', () {
    for (final g in AppColors.avatarGradients) {
      expect(g, hasLength(2));
    }
  });

  test('keine Ansicht fuehrt eine eigene Tabelle', () {
    // Der eigentliche Fehler war nicht die Farbe, sondern die Kopie: jede
    // Ansicht hatte ihre eigene Liste, und zwei davon liefen auseinander.
    final kopien = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('app_colors.dart'))
        .where((f) => RegExp(r'[aA]vatarGradients?\s*=').hasMatch(
            f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(kopien, isEmpty);
  });
}
