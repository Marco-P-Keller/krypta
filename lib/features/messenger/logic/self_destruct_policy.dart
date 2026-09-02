import '../data/models/message_model.dart';

/// Wann eine Nachricht verschwindet — und bei wem.
///
/// **Jede Frist laeuft ab der Zustellung.** Seit dem 02.09.2026 gilt das auch
/// fuer den Chat-Timer; vorher hing er am Lesen. Daniels Beispiel: Frist zehn
/// Minuten, Zustellung um 18:00, geloescht um 18:10, unabhaengig davon, ob
/// die Nachricht geoeffnet wurde.
///
/// Die Folge ist beabsichtigt: **auch Ungelesenes verschwindet**. Bis zum
/// 01.09. war es umgekehrt, damit nichts verfaellt, was niemand gesehen hat.
/// Die Umkehr ist seine Entscheidung.
///
/// Damit spielt es fuer die Zeitrechnung keine Rolle mehr, ob die Frist von
/// der Nachricht selbst oder vom Chat stammt. `selfDestructFromChat` bleibt
/// nur, weil das Feld noch auf der Leitung reist und aeltere Geraete es
/// erwarten.
///
/// **Eine Ausnahme bleibt und ist wichtig:** wird der Chat-Timer
/// nachtraeglich eingeschaltet, rechnet die Uhr ab dem **Einschalten**, nicht
/// ab der Zustellung. Ohne das waeren beim Umlegen des Schalters alle
/// aelteren Nachrichten im selben Moment ueberfaellig und der ganze sichtbare
/// Verlauf verschwaende mit einem Tipp.
///
/// Auf dem Geraet des Empfaengers ist `timestamp` der Zustellzeitpunkt, beim
/// Absender der Sendezeitpunkt. Die beiden liegen ein paar Sekunden
/// auseinander, weil der Abruf gestreut ist. Wartet die Nachricht laenger auf
/// dem Server, laeuft die Fassung des Absenders zuerst ab; anders geht es
/// nicht, solange sie dort auf ihn wartet.
abstract final class SelfDestructPolicy {
  /// Ob diese Nachricht abgelaufen ist.
  ///
  /// [now] wird hereingereicht statt selbst geholt — sonst laesst sich die
  /// Regel nicht pruefen. [chatTimer] und [chatTimerSetAt] beschreiben den
  /// Chat-Timer, wie er **jetzt** gesetzt ist; er wird bei jeder Runde neu
  /// ausgewertet und wirkt deshalb auch auf Nachrichten, die es schon vor dem
  /// Einschalten gab.
  static bool expired(
    Message m,
    DateTime now, {
    Duration? chatTimer,
    DateTime? chatTimerSetAt,
  }) {
    final ablauf =
        deadline(m, chatTimer: chatTimer, chatTimerSetAt: chatTimerSetAt);
    return ablauf != null && now.isAfter(ablauf);
  }

  /// Wann diese Nachricht faellig ist, oder `null`, wenn nie.
  static DateTime? deadline(
    Message m, {
    Duration? chatTimer,
    DateTime? chatTimerSetAt,
  }) {
    // Ein Hinweis im Verlauf laeuft nie ab. Die Dauer steht bei einem
    // Fristwechsel am Hinweis, damit der Text sie nennen kann — sie darf ihn
    // aber nicht selbst wegraeumen. Ein Hinweis, der ausgerechnet dann
    // verschwindet, wenn man ihn braucht, waere sinnlos.
    if (m.isSystemEvent) return null;

    // Die Frist der Nachricht selbst, sonst die des Chats.
    final frist = m.selfDestructDuration ?? chatTimer;
    if (frist == null) return null;

    // Gerechnet wird ab der Zustellung. `readAt` spielt keine Rolle mehr:
    // wer erst nach neun von zehn Minuten hineinschaut, hat noch eine.
    //
    // Die einzige Verschiebung ist der nachtraeglich eingeschaltete
    // Chat-Timer. Ohne sie waeren beim Umlegen des Schalters alle aelteren
    // Nachrichten sofort ueberfaellig, und der ganze sichtbare Verlauf
    // verschwaende mit einem Tipp.
    final start = chatTimerSetAt != null && chatTimerSetAt.isAfter(m.timestamp)
        ? chatTimerSetAt
        : m.timestamp;
    return start.add(frist);
  }

  /// Ob der Ablauf dieser Nachricht der Gegenseite mitzuteilen ist.
  ///
  /// Nur der Empfaenger hat `readAt` und weiss damit ueberhaupt, wann die Uhr
  /// abgelaufen ist.
  /// Burn-after-Read zaehlt mit: auch dort weiss nur der Empfaenger, wann es
  /// soweit ist — naemlich wenn er den Chat verlaesst.
  static bool announceBurn(Message m, String myId) =>
      _vergaenglich(m) && m.senderId != myId;

  /// Die kuerzeste Frist, die eine Gegenseite mir vorgeben darf.
  ///
  /// Die Frist steht in ihrer Nachricht. Ohne Untergrenze koennte sie eine
  /// schicken, die nach einer Millisekunde verschwindet — bei einem
  /// sendegebundenen Timer sogar, bevor ich sie ueberhaupt gesehen habe.
  /// Ihre Nachricht zurueckzunehmen ist ihr gutes Recht; mir die Gelegenheit
  /// zum Lesen zu stehlen nicht.
  static const Duration mindestFrist = Duration(seconds: 10);

  /// Die laengste Frist. Laenger liegt ohnehin nichts auf dem Server.
  static const Duration maximalFrist = Duration(days: 30);

  /// Eine von der Gegenseite vorgegebene Frist in vertretbare Grenzen
  /// bringen. `null` heisst: kein Timer.
  static Duration? clampFremdeFrist(int rohMs) {
    if (rohMs <= 0) return null;
    if (rohMs < mindestFrist.inMilliseconds) return mindestFrist;
    if (rohMs > maximalFrist.inMilliseconds) return maximalFrist;
    return Duration(milliseconds: rohMs);
  }

  /// Ob eine Ablaufmeldung der Gegenseite diese Nachricht entfernen darf.
  ///
  /// Zwei Bedingungen, und beide muessen halten: es muss **meine** Nachricht
  /// sein — die Gegenseite meldet ja den Ablauf dessen, was ich ihr geschickt
  /// habe — und sie muss einen Timer getragen haben. Ohne die zweite koennte
  /// eine Gegenseite mit erfundenen Ablaufmeldungen beliebige Nachrichten von
  /// meinem Geraet raeumen. Entfernt werden darf nur, was ich selbst als
  /// vergaenglich markiert habe.
  static bool acceptBurn(Message m, String myId) =>
      m.senderId == myId && _vergaenglich(m);

  /// Ob ich diese Nachricht selbst als vergaenglich markiert habe.
  ///
  /// Nur solche darf eine Ablaufmeldung der Gegenseite entfernen. Ohne diese
  /// Schranke koennte sie mit erfundenen Meldungen beliebige Nachrichten von
  /// meinem Geraet raeumen.
  static bool _vergaenglich(Message m) =>
      !m.isSystemEvent &&
      (m.selfDestructDuration != null || m.burnAfterRead);

  // ─── Der Hinweis bei einer geaenderten Chat-Frist ──────────────────────

  /// Der Anfang der Art, unter der eine geaenderte Chat-Frist reist.
  static const String artChatFrist = 'sdChanged';

  /// Die Art fuer eine Kontrollnachricht, die eine neue Chat-Frist meldet.
  ///
  /// Die Zahl steckt **in der Art**. Ihr ein eigenes Feld zu geben haette
  /// jede Signatur veraendert — ein Geraet mit einer aelteren Fassung wuerde
  /// danach auch Screenshot-Hinweise verwerfen. Die Art ist ohnehin Teil der
  /// Signatur, also faelschungssicher, und eine unbekannte Art wird von
  /// aelteren Fassungen schlicht ignoriert.
  static String artFuerChatFrist(Duration? dauer) =>
      dauer == null ? '$artChatFrist:off' : '$artChatFrist:${dauer.inMilliseconds}';

  /// Ob diese Art eine geaenderte Chat-Frist meldet.
  static bool istChatFristAenderung(String art) =>
      art.startsWith('$artChatFrist:');

  /// Die Frist aus der Art herauslesen. `null` heisst ausgeschaltet.
  ///
  /// Fail-closed: was sich nicht als positive Zahl lesen laesst, gilt als
  /// ausgeschaltet. Lieber keine Frist als eine erfundene.
  static Duration? chatFristAusArt(String art) {
    if (!istChatFristAenderung(art)) return null;
    final roh = art.substring(artChatFrist.length + 1);
    final ms = int.tryParse(roh);
    if (ms == null || ms <= 0) return null;
    return clampFremdeFrist(ms);
  }
}
