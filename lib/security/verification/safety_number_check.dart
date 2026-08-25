/// Was beim Scannen einer Sicherheitsnummer herauskommt.
enum SafetyNumberVerdict {
  /// Dieselbe Nummer — der Kontakt darf bestätigt werden.
  matches,

  /// Eine andere Nummer. Das ist eine Warnung, kein Bedienfehler.
  differs,

  /// Gar keine Sicherheitsnummer. Da wurde das Falsche gescannt.
  notASafetyNumber,
}

/// Länge einer Sicherheitsnummer: 30 Ziffern je Seite.
const int _digits = 60;

/// Eine gescannte Sicherheitsnummer gegen die eigene halten.
///
/// Die Nummer ist symmetrisch — beide Seiten rechnen aus denselben
/// Identitätsschlüsseln dieselben 60 Ziffern aus. Zeigt das andere Gerät
/// dieselbe Zahl, hat niemand dazwischengefunkt. Das ist derselbe Nachweis
/// wie das Vergleichen mit dem Auge, nur ohne 60 Ziffern abzulesen.
///
/// Die drei Ausgänge werden bewusst getrennt gehalten. „Stimmt nicht
/// überein" darf nie als „unlesbar" durchgehen: ein Angriff sieht aus wie
/// eine falsche Nummer, nicht wie ein Lesefehler. Und umgekehrt soll ein
/// versehentlich gescannter Kontakt-QR-Code keine Warnung auslösen —
/// da hat niemand angegriffen.
SafetyNumberVerdict checkScannedSafetyNumber({
  required String scanned,
  required String expected,
}) {
  final gescannt = _nurZiffern(scanned);
  final eigene = _nurZiffern(expected);

  // Fail-closed: ohne eigene Nummer gibt es nichts zu vergleichen, und
  // eine Bestätigung ohne Vergleich wäre schlimmer als keine.
  if (eigene.length != _digits) return SafetyNumberVerdict.notASafetyNumber;
  if (gescannt.length != _digits) return SafetyNumberVerdict.notASafetyNumber;

  return gescannt == eigene
      ? SafetyNumberVerdict.matches
      : SafetyNumberVerdict.differs;
}

/// Leerzeichen und Zeilenumbrüche entfernen — die Anzeige gruppiert die
/// Ziffern zu Fünferblöcken, und wer den angezeigten Text kopiert, bringt
/// sie mit. Alles andere bleibt stehen, damit ein fremder QR-Code nicht
/// versehentlich zu einer gültigen Nummer zurechtgeputzt wird.
String _nurZiffern(String roh) => roh.replaceAll(RegExp(r'\s'), '');
