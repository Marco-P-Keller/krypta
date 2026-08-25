import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/verification/safety_number_check.dart';

/// Was beim Scannen einer Sicherheitsnummer herauskommen darf.
///
/// Die Nummer ist symmetrisch: beide Seiten rechnen aus denselben
/// Identitätsschlüsseln dieselben 60 Ziffern aus. Zeigt das andere Gerät
/// dieselbe Zahl, hat niemand dazwischengefunkt — genau das prüft das
/// Scannen, nur ohne 60 Ziffern mit dem Auge zu vergleichen.
///
/// Drei Ausgänge, und der mittlere ist der wichtigste: „stimmt nicht
/// überein" darf nie als „unlesbar" durchgehen. Ein Angriff sieht aus wie
/// eine falsche Nummer, nicht wie ein Lesefehler.
void main() {
  const meine = '111112222233333444445555566666'
      '777778888899999000001111122222';
  const andere = '999998888877777666665555544444'
      '333332222211111000009999988888';

  test('dieselbe Nummer ist eine Bestaetigung', () {
    expect(
      checkScannedSafetyNumber(scanned: meine, expected: meine),
      SafetyNumberVerdict.matches,
    );
  });

  test('Leerzeichen aus der Anzeige stoeren nicht', () {
    // formatForDisplay setzt Gruppen zu fuenf Ziffern; wer den angezeigten
    // Text scannt oder einfuegt, bringt sie mit.
    final mitLuecken = '${meine.substring(0, 5)} ${meine.substring(5, 10)} '
        '${meine.substring(10)}';

    expect(
      checkScannedSafetyNumber(scanned: mitLuecken, expected: meine),
      SafetyNumberVerdict.matches,
    );
  });

  test('eine andere Nummer ist eine Warnung, kein Lesefehler', () {
    expect(
      checkScannedSafetyNumber(scanned: andere, expected: meine),
      SafetyNumberVerdict.differs,
    );
  });

  test('eine einzige abweichende Ziffer genuegt', () {
    final fast = '${meine.substring(0, 59)}${meine[59] == '2' ? '3' : '2'}';

    expect(
      checkScannedSafetyNumber(scanned: fast, expected: meine),
      SafetyNumberVerdict.differs,
    );
  });

  test('ein fremder QR-Code ist unlesbar, nicht falsch', () {
    // Etwa der Kontakt-QR-Code, der JSON enthaelt. Dafuer eine Warnung
    // auszugeben waere irrefuehrend — da hat niemand angegriffen, da wurde
    // das Falsche gescannt.
    for (final murks in ['{"v":2,"uid":"abc"}', '', '   ', 'https://example.org']) {
      expect(
        checkScannedSafetyNumber(scanned: murks, expected: meine),
        SafetyNumberVerdict.notASafetyNumber,
        reason: murks,
      );
    }
  });

  test('zu kurz oder zu lang zaehlt nicht als Nummer', () {
    expect(
      checkScannedSafetyNumber(scanned: meine.substring(0, 59), expected: meine),
      SafetyNumberVerdict.notASafetyNumber,
    );
    expect(
      checkScannedSafetyNumber(scanned: '${meine}7', expected: meine),
      SafetyNumberVerdict.notASafetyNumber,
    );
  });

  test('ohne eigene Nummer wird nichts bestaetigt', () {
    // Fail-closed: lieber keine Aussage als eine falsche.
    expect(
      checkScannedSafetyNumber(scanned: meine, expected: ''),
      SafetyNumberVerdict.notASafetyNumber,
    );
  });
}
