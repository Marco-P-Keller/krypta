/// Welche Beschriftung zu einer Loeschfrist gehoert.
///
/// Der Anlass: in der Auswahl stand „1 Std." zweimal. Die Zuordnung lag als
/// Kette von Vergleichen mitten im Einstellungsblatt, und die Reihenfolge war
/// falsch — bei dreissig Minuten ist `inMinutes` schon groesser als fuenf,
/// `inHours` aber noch null, also griff `inHours <= 1`. Dreissig Minuten
/// hiessen dadurch „1 Std.".
///
/// Die Zuordnung steht deshalb hier und nicht in der Oberflaeche: sie ist
/// eine Regel, keine Darstellung, und so ist sie pruefbar.
enum FristStufe {
  aus,
  sekunden30,
  minuten5,
  minuten30,
  stunde1,
  tag1,
  woche1,

  /// Keine Frist, sondern ein Ereignis: was gelesen ist, geht beim Verlassen
  /// des Chats. Steht in der Auswahl neben den Zeiten und braucht deshalb
  /// eine eigene Stufe — sonst stuende dort „Aus".
  nachLesen,
}

abstract final class FristLabel {
  /// Die Stufe zu einer Dauer. Die Reihenfolge der Vergleiche ist die
  /// eigentliche Aussage: jede Schwelle muss geprueft werden, bevor die
  /// naechstgroebere greift.
  static FristStufe stufe(Duration? d) {
    if (d == null) return FristStufe.aus;
    if (d.inSeconds <= 30) return FristStufe.sekunden30;
    if (d.inMinutes <= 5) return FristStufe.minuten5;
    if (d.inMinutes <= 30) return FristStufe.minuten30;
    if (d.inHours <= 1) return FristStufe.stunde1;
    if (d.inDays <= 1) return FristStufe.tag1;
    return FristStufe.woche1;
  }

  /// Die Stufe zur ganzen Loeschregel eines Chats.
  ///
  /// Die Regel ist mehr als eine Dauer: sie kann auch „Direkt nach dem Lesen"
  /// sein. Wer nur [stufe] fragt, sieht davon nichts.
  static FristStufe stufeFuerRegel({Duration? frist, bool nachLesen = false}) =>
      nachLesen ? FristStufe.nachLesen : stufe(frist);
}
