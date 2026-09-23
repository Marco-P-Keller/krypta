/// Was die App zeigt, wenn sie gesperrt ist — und ob sie ueberhaupt sperrt.
///
/// Der Taschenrechner ist seit dem 22.09.2026 freiwillig. Damit gibt es die
/// Frage „wohin faellt die App beim Weglegen?" ueberhaupt erst: vorher war die
/// Antwort immer der Rechner.
///
/// Steht als eigene Regel hier, weil die Huelle in `app.dart` an einem
/// `BuildContext`, an Firebase und am Schluesselbund haengt und darum nicht im
/// Test laeuft. Die Hausregel dieses Projekts, siehe UnreadPolicy und
/// SelfDestructPolicy.
enum Sperrziel {
  /// Der Taschenrechner. Er geht vor: wer ihn anhat, soll ihn sehen, auch
  /// wenn zusaetzlich ein Tresor-Passwort gesetzt ist.
  rechner,

  /// Der Sperrbildschirm ohne Verkleidung. Er sagt offen, dass die App
  /// gesperrt ist, und entsperrt ueber Face ID beziehungsweise das
  /// Tresor-Passwort.
  sperrbildschirm,

  /// Gar nicht sperren.
  ///
  /// Kein Rechner, kein Tresor-Passwort, keine Biometrie: dann gibt es nichts
  /// zu pruefen. Ein Bildschirm, den ein einziger Tipp oeffnet, waere keine
  /// Sperre, sondern nur eine Huerde fuer den Besitzer — und er wuerde eine
  /// Sicherheit behaupten, die es nicht gibt. Genau diese Ehrlichkeit hat das
  /// Projekt beim Screenshot-Schutz schon einmal teuer gelernt.
  offen,
}

abstract final class ZugangsPolicy {
  /// Wohin die App faellt, wenn sie sperrt.
  static Sperrziel ziel({
    required bool rechner,
    required bool tresor,
    required bool biometrie,
  }) {
    if (rechner) return Sperrziel.rechner;
    if (tresor || biometrie) return Sperrziel.sperrbildschirm;
    return Sperrziel.offen;
  }

  /// Ob es ueberhaupt etwas zu sperren gibt.
  ///
  /// Haengt der Pfeil links oben in der Chatliste daran: ohne Ziel keine
  /// Schaltflaeche.
  static bool sperrbar({
    required bool rechner,
    required bool tresor,
    required bool biometrie,
  }) =>
      ziel(rechner: rechner, tresor: tresor, biometrie: biometrie) !=
      Sperrziel.offen;
}
