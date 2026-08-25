/// Buchhaltung darueber, welcher Chat von welcher Bildschirmaufnahme schon
/// erfahren hat.
///
/// Eine Aufnahme laeuft weiter, waehrend man durch die App navigiert. Der
/// Chat-Bildschirm wird dabei jedes Mal neu gebaut und fragt erneut nach —
/// ohne diese Buchhaltung saehe die Gegenseite fuer EINE Aufnahme bei jedem
/// Oeffnen des Chats erneut „Bildschirmaufnahme gestartet".
///
/// Die Nummer der Aufnahme kommt vom [PlatformSecurityService], der sie
/// lueckenlos mitzaehlt. Nur so laesst sich „dieselbe Aufnahme wie eben" von
/// „eine neue Aufnahme" unterscheiden.
class RecordingNoticePolicy {
  /// Chat-Kennung -> Nummer der zuletzt gemeldeten Aufnahme.
  final Map<String, int> _announced = {};

  /// Obergrenze der Buchhaltung. Sie waechst sonst mit jedem je geoeffneten
  /// Chat; wer den aeltesten Eintrag verliert, bekommt schlimmstenfalls eine
  /// Meldung doppelt — das ist die harmlosere Richtung.
  static const int maxChats = 200;

  int get trackedChats => _announced.length;

  /// Ob dieser Chat von Aufnahme [session] noch erfahren muss.
  ///
  /// [session] ist `0`, wenn gerade keine Aufnahme laeuft — dann gibt es
  /// nichts zu melden.
  bool shouldAnnounce(String chatId, int session) {
    if (session == 0) return false;
    if (_announced[chatId] == session) return false;
    // Dart haelt die Einfuegereihenfolge, also ist der erste Schluessel der
    // aelteste.
    if (_announced.length >= maxChats && !_announced.containsKey(chatId)) {
      _announced.remove(_announced.keys.first);
    }
    _announced[chatId] = session;
    return true;
  }

  void clear() => _announced.clear();
}
