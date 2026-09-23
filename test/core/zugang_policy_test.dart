import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/auth/logic/zugang_policy.dart';

/// Wohin die App faellt, wenn sie gesperrt wird.
///
/// Daniels Liste vom 22.09.2026: „TR soll optional sein und in den
/// Einstellungen jederzeit ein- und ausgeschaltet werden können." Damit gibt
/// es diese Frage ueberhaupt erst — vorher war die Antwort immer der
/// Taschenrechner.
void main() {
  test('mit Rechner faellt sie auf den Rechner', () {
    expect(
      ZugangsPolicy.ziel(rechner: true, tresor: false, biometrie: false),
      Sperrziel.rechner,
    );
  });

  test('der Rechner geht vor, auch neben Tresor und Face ID', () {
    // Wer ihn anhat, soll ihn sehen. Was danach kommt, prueft ohnehin
    // zusaetzlich.
    expect(
      ZugangsPolicy.ziel(rechner: true, tresor: true, biometrie: true),
      Sperrziel.rechner,
    );
  });

  test('ohne Rechner, aber mit Tresor-Passwort: der Sperrbildschirm', () {
    expect(
      ZugangsPolicy.ziel(rechner: false, tresor: true, biometrie: false),
      Sperrziel.sperrbildschirm,
    );
  });

  test('ohne Rechner, aber mit Face ID: der Sperrbildschirm', () {
    expect(
      ZugangsPolicy.ziel(rechner: false, tresor: false, biometrie: true),
      Sperrziel.sperrbildschirm,
    );
  });

  test('ohne alles wird nicht gesperrt', () {
    // Ein Bildschirm, den ein einziger Tipp oeffnet, ist keine Sperre — er
    // behauptet nur eine.
    expect(
      ZugangsPolicy.ziel(rechner: false, tresor: false, biometrie: false),
      Sperrziel.offen,
    );
    expect(
      ZugangsPolicy.sperrbar(
          rechner: false, tresor: false, biometrie: false),
      isFalse,
      reason: 'daran haengt der Pfeil links oben in der Chatliste',
    );
  });

  test('sobald etwas schuetzt, ist die App sperrbar', () {
    for (final fall in [
      (rechner: true, tresor: false, biometrie: false),
      (rechner: false, tresor: true, biometrie: false),
      (rechner: false, tresor: false, biometrie: true),
    ]) {
      expect(
        ZugangsPolicy.sperrbar(
            rechner: fall.rechner,
            tresor: fall.tresor,
            biometrie: fall.biometrie),
        isTrue,
        reason: '$fall',
      );
    }
  });
}
