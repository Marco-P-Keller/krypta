/// Die Wartetreppe, mit der sich der Inbox-Listener nach einem Abriss wieder
/// anhängt.
///
/// Reißt die Firestore-Verbindung ab, wird nicht sofort wieder angeklopft:
/// jeder Fehlversuch verdoppelt die Wartezeit, bis zum [deckel]. Ohne diese
/// Bremse würde ein dauerhafter Fehler — entzogene Rechte etwa — in eine enge
/// Wiederholschleife laufen.
///
/// Der Teil, der hier lange gefehlt hat, ist [angekommen]. Ein Zähler, der nur
/// klettern kann, schleppt eine überstandene Nacht im Hintergrund als
/// „siebter Fehlversuch in Folge" mit sich herum. Beim Aufwachen kostete dann
/// der erste Versuch — der ganz normal daran scheitert, dass das Netz noch
/// nicht wieder steht — eine volle Minute Stille, bevor überhaupt ein zweiter
/// kam. Genau so lag eine Kontaktanfrage vom Vormittag noch eine Minute
/// herum, obwohl die Chatliste längst auf dem Schirm war.
///
/// Sobald ein Snapshot ankommt, steht die Verbindung — und die Treppe gehört
/// zurück auf null.
class InboxReconnectBackoff {
  /// Die längste Wartezeit zwischen zwei Versuchen.
  static const Duration deckel = Duration(seconds: 60);

  /// Ab diesem Stand greift der [deckel]: 1, 2, 4, 8, 16, 32, dann 60.
  static const int _stufenBisDeckel = 6;

  int _fehlversuche = 0;

  /// Wie viele Fehlversuche seit dem letzten Snapshot aufgelaufen sind.
  int get fehlversuche => _fehlversuche;

  /// Einen Fehlversuch verbuchen und sagen, wie lange bis zum nächsten zu
  /// warten ist.
  Duration nachFehlversuch() {
    final sekunden = _fehlversuche >= _stufenBisDeckel
        ? deckel.inSeconds
        : 1 << _fehlversuche;
    _fehlversuche++;
    return Duration(seconds: sekunden);
  }

  /// Ein Snapshot ist angekommen: die Verbindung steht, die Treppe fällt
  /// zurück auf null.
  void angekommen() => _fehlversuche = 0;
}
