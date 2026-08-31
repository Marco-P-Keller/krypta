import '../data/models/message_model.dart';

/// Wann eine Nachricht verschwindet — und bei wem.
///
/// Es gibt **zwei** Timer, und sie bedeuten Verschiedenes.
///
/// **Der Timer einer einzelnen Nachricht** ist ein Versprechen an die
/// Gegenseite. Er laeuft ab dem **Lesen** — vorher hat sie die Nachricht ja
/// noch nicht gesehen — und raeumt auf beiden Geraeten auf. `readAt` setzt
/// dabei nur der Empfaenger; beim Absender bleibt es leer, solange keine
/// Lesebestaetigung kommt, und die ist standardmaessig aus. Seine Fassung lief
/// deshalb nie ab: beim Empfaenger vernichtet, bei ihm noch da. Darum meldet
/// der Empfaenger den Ablauf — siehe [announceBurn].
///
/// **Der Chat-Timer** ist Hausordnung fuer diesen Chat. Er laeuft ab dem
/// **Senden** und raeumt auch auf, wenn nie jemand hinsieht. Wird er
/// nachtraeglich eingeschaltet, gilt er auch fuer das, was schon dasteht —
/// dann ab dem Einschalten, damit nicht mit einem Tipp der halbe Verlauf im
/// selben Moment verschwindet.
///
/// Hat eine Nachricht einen eigenen Timer, schlaegt der den Chat-Timer, in
/// beide Richtungen: laenger wie kuerzer.
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
    final eigener = m.selfDestructDuration;
    if (eigener != null) {
      // Der Chat-Timer wird beim Senden mit hineingeschrieben, damit er auf
      // beiden Seiten ueberhaupt greift. Er laeuft ab dem Senden, nicht ab
      // dem Lesen.
      //
      // Die beiden Fristen sind **nicht auf die Sekunde gleich**: der
      // Empfaenger setzt den Zeitstempel beim Verarbeiten, nicht beim
      // Absenden. War er zwei Tage offline, behaelt er die Nachricht ab
      // Zustellung noch die volle Frist, waehrend sie beim Absender laengst
      // weg ist. Die Abweichung geht also immer in die harmlose Richtung —
      // nichts verschwindet frueher als zugesagt. Sie ganz auszuraeumen
      // hiesse, die Absenderzeit mitzuschicken und ihr zu trauen; das waere
      // ein Knopf, mit dem die Gegenseite meine Fassung vorzeitig raeumt.
      if (m.selfDestructFromSend) return m.timestamp.add(eigener);
      final gelesen = m.readAt;
      // Ungelesen laeuft die Uhr nicht. Ein Timer, der abliefe, bevor die
      // Nachricht ueberhaupt jemand gesehen hat, haette sie nie zugestellt.
      if (gelesen == null) return null;
      return gelesen.add(eigener);
    }

    if (chatTimer == null) return null;
    // Nachtraeglich eingeschaltet: was aelter ist als das Einschalten, bekommt
    // die volle Frist ab dem Einschalten.
    final start = chatTimerSetAt != null && chatTimerSetAt.isAfter(m.timestamp)
        ? chatTimerSetAt
        : m.timestamp;
    return start.add(chatTimer);
  }

  /// Ob der Ablauf dieser Nachricht der Gegenseite mitzuteilen ist.
  ///
  /// Nur beim **lesegebundenen** Timer: dort weiss allein der Empfaenger, wann
  /// die Uhr abgelaufen ist. Ein sendegebundener Timer laeuft auf beiden
  /// Geraeten aus derselben Rechnung ab — da ist nichts mitzuteilen, und eine
  /// Meldung waere nur zusaetzliche Spur.
  static bool announceBurn(Message m, String myId) =>
      m.selfDestructDuration != null &&
      !m.selfDestructFromSend &&
      m.senderId != myId;

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
  /// **Sendegebundene sind ausgenommen.** Deren Frist kenne ich selbst, mein
  /// eigener Takt raeumt sie weg, und eine Meldung dafuer gibt es gar nicht
  /// ([announceBurn] verschickt keine). Sie anzunehmen hiesse nur, der
  /// Gegenseite einen Knopf zu geben, mit dem sie meine Fassung vorzeitig
  /// loeschen kann.
  static bool acceptBurn(Message m, String myId) =>
      m.senderId == myId &&
      m.selfDestructDuration != null &&
      !m.selfDestructFromSend;
}
