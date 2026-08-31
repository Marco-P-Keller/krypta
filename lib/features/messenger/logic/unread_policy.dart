import '../data/models/message_model.dart';

/// Wie viele Nachrichten ungelesen sind und wann die erste davon kam.
typedef UngelesenStand = ({int anzahl, DateTime? ersteNeue});

/// Der Stand der Chatliste, aus dem gerechnet, was noch da ist.
///
/// Zaehler und Uhrzeit wurden bisher nur beim Eintreffen fortgeschrieben.
/// Verschwanden Nachrichten danach — ein Loeschtimer lief ab, die Gegenseite
/// warf ihren Chat weg —, blieben beide stehen. In der Liste stand dann
/// „3 neue" fuer einen Chat, in dem nichts mehr liegt.
///
/// Statt nachzurechnen, was abzuziehen waere, wird neu gezaehlt, was uebrig
/// ist. Das kann nicht auseinanderlaufen.
abstract final class UnreadPolicy {
  /// Ungelesen ist, was die Gegenseite geschickt hat und was noch kein
  /// `readAt` traegt. Die Uhrzeit ist die der **aeltesten** davon — sie soll
  /// stehenbleiben, waehrend weitere hereinkommen.
  static UngelesenStand zaehle(Iterable<Message> messages, String myId) {
    var anzahl = 0;
    DateTime? erste;

    for (final m in messages) {
      if (m.senderId == myId) continue;
      if (m.readAt != null) continue;
      anzahl++;
      if (erste == null || m.timestamp.isBefore(erste)) erste = m.timestamp;
    }

    return (anzahl: anzahl, ersteNeue: erste);
  }
}
