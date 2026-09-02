/// Was ein gescannter QR-Code mitbringen muss, bevor er den Server befragt.
///
/// Der Anlass: eine externe Durchsicht am 02.09.2026 bemaengelte, dass der
/// Scanner den Inhalt zu grosszuegig annimmt. Drei Luecken hielten der
/// Gegenprobe stand — es fehlten eine Obergrenze fuer die Rohdaten, die
/// **exakte** Schluessellaenge (geprueft wurde nur „nicht leer") und die
/// Pruefung der Nutzerkennung, bevor mit ihr der Server befragt wird.
///
/// Die Regeln stehen hier und nicht im Bildschirm, weil ein Parser ohne Test
/// genau die Stelle ist, an der so etwas wieder einreisst.
abstract final class QrPayloadPolicy {
  /// Obergrenze fuer die Rohdaten eines QR-Codes.
  ///
  /// Ein echter Krypta-Code liegt bei rund 300 Zeichen: Kennung, Schluessel,
  /// Fingerprint, Token. Zwei Kilobyte lassen reichlich Luft und schneiden
  /// trotzdem alles ab, was jemand hineinzuschmuggeln versucht, bevor
  /// ueberhaupt geparst wird.
  static const int maxRohlaenge = 2048;

  /// Laenge eines X25519-Public-Keys in Bytes.
  ///
  /// RFC 7748 legt Ein- und Ausgaben auf 32 Byte fest. Vorher wurde nur auf
  /// „nicht leer" geprueft, ein Schluessel beliebiger Laenge kam also bis zur
  /// Fingerprint-Pruefung durch.
  static const int schluessellaenge = 32;

  /// Obergrenze fuer die einzelnen Textfelder.
  static const int maxFeldlaenge = 256;

  static bool rohdatenPassen(String raw) =>
      raw.isNotEmpty && raw.length <= maxRohlaenge;

  static bool schluesselPasst(int laengeInBytes) =>
      laengeInBytes == schluessellaenge;

  static bool feldPasst(String wert) =>
      wert.isNotEmpty && wert.length <= maxFeldlaenge;

  /// Nutzerkennung im Format von Firebase Auth.
  ///
  /// Dieselbe Regel wie im ID-Weg — der Provider ruft sie hier ab, statt eine
  /// zweite Fassung zu halten. Zwei Fassungen derselben Regel laufen
  /// frueher oder spaeter auseinander, und dann ist die eine strenger als die
  /// andere.
  static bool userIdPasst(String id) {
    if (id.length < 10 || id.length > 128) return false;
    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id);
  }
}
