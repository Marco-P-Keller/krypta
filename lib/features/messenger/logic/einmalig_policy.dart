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

  /// Ob die Blase den Inhalt verbergen muss.
  ///
  /// Auf **beiden** Seiten, seit Daniels Entscheidung vom 04.09.2026. Bis
  /// dahin sah der Absender seinen eigenen Text weiter in der Blase stehen.
  /// Das war die schwaechste Stelle der ganzen Zusage: wer dem Absender ueber
  /// die Schulter sah oder sein Geraet in die Hand bekam, las den Text ohne
  /// jedes Tor — waehrend der Empfaenger ihn nur ein einziges Mal zu sehen
  /// bekam. Eine Nachricht, die nur einmal zu oeffnen ist, darf auf keinem
  /// der beiden Geraete offen herumliegen.
  ///
  /// Der Absender sieht darum nur noch, **dass** er eine einmalige Nachricht
  /// geschickt hat, mit Uhrzeit und Zustellstand. Was drinsteht, weiss er
  /// ohnehin — er hat es geschrieben.
  static bool verbergen({required bool einmalig}) => einmalig;

  /// Ob diese Seite die Nachricht oeffnen darf.
  ///
  /// Nur der Empfaenger. Beim Absender gaebe es nichts zu oeffnen: sein
  /// Klartext wird gar nicht erst gespeichert, siehe [klartextBeimAbsender].
  static bool oeffenbar({
    required bool einmalig,
    required String senderId,
    required String? eigeneId,
  }) =>
      einmalig && senderId != eigeneId;

  /// Ob der Absender den Klartext seiner eigenen Nachricht behaelt.
  ///
  /// Bei einer einmaligen Nachricht nicht. Ihn nur in der Blase auszublenden
  /// waere Kosmetik — der Text laege trotzdem im lokalen Speicher und damit
  /// in jedem Auszug daraus. Er wird gesendet und danach fallen gelassen.
  ///
  /// Das ist kein Verlust: die Blase zeigt beim Absender ohnehin nichts mehr
  /// vom Inhalt, und sobald die Gegenseite geoeffnet hat, verschwindet der
  /// Eintrag auf beiden Geraeten ganz.
  static bool klartextBeimAbsender({required bool einmalig}) => !einmalig;

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
