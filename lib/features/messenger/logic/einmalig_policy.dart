/// Die einmalige Nachricht: wann sie verborgen wird, und woran sie zu
/// erkennen ist.
///
/// Sie ersetzt seit dem 02.09.2026 den Loeschtimer einzelner Nachrichten und
/// Burn after read. Die Entscheidungen stehen hier und nicht im Provider,
/// weil der Firebase braucht und darum nicht im Test laeuft. Das ist die
/// Hausregel dieses Projekts, siehe UnreadPolicy und VerificationPolicy.
abstract final class EinmaligPolicy {
  /// Das Feld im inneren Payload.
  static const String feldName = '_once';

  /// Ob die Blase den Inhalt verbergen und stattdessen die Schaltflaeche
  /// zeigen muss.
  ///
  /// Beim Absender nie: er sieht seinen eigenen Text, bis die Gegenseite
  /// geoeffnet hat. Danach ist die Nachricht auch bei ihm fort.
  static bool verbergen({
    required bool einmalig,
    required String senderId,
    required String? eigeneId,
  }) =>
      einmalig && senderId != eigeneId;

  /// Ob eine eintreffende Nachricht als einmalig gilt.
  ///
  /// Liest ausschliesslich [feldName]. Das alte `_bar` bleibt bewusst aussen
  /// vor: ein aelterer Absender hat seiner Gegenseite Burn after read
  /// zugesagt, also Inhalt sichtbar und weg beim Verlassen. Daraus
  /// nachtraeglich eine Nachricht mit Tor und Bestaetigung zu machen hiesse,
  /// seine Zusage im Nachhinein zu aendern.
  static bool ausPayload(Map<String, dynamic> payload) =>
      payload[feldName] == true || payload[feldName] == 'true';
}
