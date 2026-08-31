import '../data/models/message_model.dart';

/// Wann eine Nachricht verschwindet — und bei wem.
///
/// Es gibt zwei Timer, und **beide laufen ab dem Lesen**. Ein Timer, der
/// abliefe, bevor die Nachricht ueberhaupt jemand gesehen hat, haette sie nie
/// zugestellt.
///
/// Der Preis davon, offen benannt: **Ungelesenes laeuft nie ab.** Ein Chat
/// mit 24-Stunden-Regel raeumt nichts weg, was niemand geoeffnet hat. Der
/// Chat-Timer lief einen Tag lang ab dem Senden und haette das erledigt;
/// Daniel wollte am 31.08. das eine Modell fuer beide Timer.
///
/// `readAt` setzt nur der Empfaenger. Beim Absender bleibt es leer, solange
/// keine Lesebestaetigung kommt, und die ist standardmaessig aus — seine
/// Fassung lief deshalb nie ab: beim Empfaenger vernichtet, bei ihm noch da.
/// Darum meldet der Empfaenger den Ablauf, siehe [announceBurn].
///
/// Der Unterschied zwischen den beiden liegt woanders: der **Chat-Timer**
/// gilt auch fuer das, was schon dasteht — dann ab dem **Einschalten**, damit
/// nicht mit einem Tipp der halbe Verlauf im selben Moment verschwindet. Und
/// ein eigener Timer der Nachricht schlaegt ihn, in beide Richtungen.
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
    final gelesen = m.readAt;
    // Ungelesen laeuft keine Uhr. Gilt fuer beide Timer.
    if (gelesen == null) return null;

    final eigener = m.selfDestructDuration;
    if (eigener != null) return gelesen.add(eigener);

    if (chatTimer == null) return null;
    // Nachtraeglich eingeschaltet: was schon gelesen war, bekommt die volle
    // Frist ab dem Einschalten.
    final start = chatTimerSetAt != null && chatTimerSetAt.isAfter(gelesen)
        ? chatTimerSetAt
        : gelesen;
    return start.add(chatTimer);
  }

  /// Ob der Ablauf dieser Nachricht der Gegenseite mitzuteilen ist.
  ///
  /// Nur der Empfaenger hat `readAt` und weiss damit ueberhaupt, wann die Uhr
  /// abgelaufen ist.
  static bool announceBurn(Message m, String myId) =>
      m.selfDestructDuration != null && m.senderId != myId;

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
      m.senderId == myId && m.selfDestructDuration != null;
}
