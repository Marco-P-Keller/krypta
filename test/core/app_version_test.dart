import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/core/constants/app_constants.dart';

/// Die Versionsanzeige im Einstellungs-Bildschirm stand jahrelang auf einer
/// fest verdrahteten '1.0.0', wahrend im App Store schon 4.0.0 auslieferte.
/// Gefunden wurde das erst beim Geraetetest von Build 85 — kein Test hatte je
/// hingeschaut. Diese Tests decken die Formatierung ab; die Werte selbst
/// kommen ueber --dart-define aus pubspec.yaml.
void main() {
  group('AppConstants.formatVersion', () {
    test('Version und Build werden zusammengesetzt', () {
      expect(AppConstants.formatVersion('4.1.0', '85'), '4.1.0 (85)');
    });

    test('ohne Build-Nummer bleibt die nackte Version stehen', () {
      expect(AppConstants.formatVersion('4.1.0', ''), '4.1.0');
    });

    test('ohne Version steht dev da, nicht eine erfundene Zahl', () {
      // Der eigentliche Punkt: lieber ehrlich "dev" als eine Zahl behaupten,
      // die niemand gesetzt hat.
      expect(AppConstants.formatVersion('', ''), 'dev');
      expect(AppConstants.formatVersion('', '85'), 'dev');
    });

    test('Leerraum aus den Defines faellt weg', () {
      expect(AppConstants.formatVersion(' 4.1.0 ', ' 85 '), '4.1.0 (85)');
      expect(AppConstants.formatVersion('   ', ''), 'dev');
    });
  });

  test('appVersion liefert nie einen leeren String', () {
    // Ohne --dart-define im Testlauf ist das 'dev'; im CI-Build die echte
    // Version. Beides ist etwas, das man dem Nutzer zeigen kann.
    expect(AppConstants.appVersion, isNotEmpty);
  });
}
