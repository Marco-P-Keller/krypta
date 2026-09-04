import '../data/models/message_model.dart';

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
  ///
  /// [eigeneId] ist die **angemeldete** Kennung, nicht eine aus der Nachricht
  /// abgeleitete. Wer hier `senderId` oder `recipientId` je nach Seite
  /// hereinreicht, prueft nur seinen eigenen Schalter noch einmal und nennt
  /// es Identitaet. Fehlt die Kennung, gibt es kein Tor: die sichere Antwort
  /// ist zu, nicht offen fuer jeden.
  static bool oeffenbar({
    required bool einmalig,
    required String senderId,
    required String? eigeneId,
  }) =>
      einmalig && eigeneId != null && senderId != eigeneId;

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

  /// Ob dieser bereits gespeicherte Eintrag seinen Klartext noch hergeben
  /// muss.
  ///
  /// [klartextBeimAbsender] greift erst beim Senden und damit nur fuer neue
  /// Nachrichten. Was ich zwischen dem 02.09. und dem 04.09.2026 einmalig
  /// verschickt habe, liegt weiter mit Klartext auf der Platte: damals wurde
  /// er beim Senden behalten, und die Ablaufmeldung der Gegenseite verwarf
  /// SelfDestructPolicy.acceptBurn, weil `_vergaenglich` `einmalig` nicht
  /// mitzaehlte. Eine zweite Meldung kommt fuer diese Nachrichten nie.
  ///
  /// Seit dem 04.09. zeigt die Blase davon nichts mehr — und genau das ist
  /// die Kosmetik, vor der [klartextBeimAbsender] warnt: unsichtbar, aber im
  /// Speicher und damit in jedem Auszug daraus. Der Bestand wird deshalb beim
  /// Laden nachgeraeumt.
  ///
  /// Nur **meine eigenen**: die Nachricht der Gegenseite ist einmal zu
  /// oeffnen, ihr Klartext wird beim Oeffnen verbraucht. Ohne [eigeneId] —
  /// beim Start noch nicht angemeldet — wird nichts angetastet; eine leere
  /// Kennung darf nicht auf einen leeren Absender passen.
  static bool nachzuraeumen(Message m, String eigeneId) =>
      m.einmalig &&
      m.decryptedContent != null &&
      eigeneId.isNotEmpty &&
      m.senderId == eigeneId;

  /// Raeumt den Bestand eines Chats nach und sagt, ob sich etwas geaendert
  /// hat.
  ///
  /// Nur dann muss der Aufrufer speichern — sonst schriebe jeder Start jeden
  /// Chat neu. Die Liste wird an Ort und Stelle geaendert, wie sie auch im
  /// Provider liegt.
  static bool nachraeumen(List<Message> messages, String eigeneId) {
    var geaendert = false;
    for (var i = 0; i < messages.length; i++) {
      if (!nachzuraeumen(messages[i], eigeneId)) continue;
      messages[i] = messages[i].copyWith(decryptedContent: null);
      geaendert = true;
    }
    return geaendert;
  }

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
