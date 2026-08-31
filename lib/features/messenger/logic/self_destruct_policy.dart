import '../data/models/message_model.dart';

/// Wann eine Nachricht mit Loeschtimer verschwindet — und bei wem.
///
/// Die Uhr laeuft **ab dem Lesen**, nicht ab dem Senden. `readAt` setzt aber
/// nur der Empfaenger: beim Absender bleibt es leer, solange keine
/// Lesebestaetigung kommt, und die ist standardmaessig aus. Seine Fassung lief
/// deshalb nie ab und blieb fuer immer liegen — die Nachricht war beim
/// Empfaenger vernichtet und beim Absender noch da.
///
/// Deshalb sagt der Empfaenger jetzt Bescheid, sobald die Uhr abgelaufen ist.
///
/// **Was das verraet:** der Absender erfaehrt damit ungefaehr, wann gelesen
/// wurde — Ablauf minus Timerdauer. Das laesst sich nicht vermeiden, wenn die
/// Nachricht auf beiden Seiten verschwinden soll, und es betrifft
/// ausschliesslich Nachrichten, die er selbst als vergaenglich markiert hat.
/// Die Meldung geht mit derselben zeitlichen Streuung raus wie die
/// Empfangsbestaetigungen, damit der Zeitpunkt nicht auf die Sekunde genau
/// ablesbar ist.
abstract final class SelfDestructPolicy {
  /// Ob diese Nachricht abgelaufen ist.
  ///
  /// [now] wird hereingereicht statt selbst geholt — sonst laesst sich die
  /// Regel nicht pruefen.
  static bool expired(Message m, DateTime now) {
    final dauer = m.selfDestructDuration;
    final gelesen = m.readAt;
    if (dauer == null) return false;
    // Ungelesen laeuft die Uhr nicht. Das ist Absicht: ein Timer, der schon
    // abgelaufen waere, bevor die Nachricht ueberhaupt jemand gesehen hat,
    // haette die Nachricht nie zugestellt.
    if (gelesen == null) return false;
    return now.isAfter(gelesen.add(dauer));
  }

  /// Ob der Ablauf dieser Nachricht der Gegenseite mitzuteilen ist.
  ///
  /// Nur der Empfaenger meldet: nur er hat [Message.readAt] und weiss damit
  /// ueberhaupt, wann die Uhr abgelaufen ist.
  static bool announceBurn(Message m, String myId) =>
      m.selfDestructDuration != null && m.senderId != myId;

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
