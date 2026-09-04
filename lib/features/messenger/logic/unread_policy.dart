import '../data/models/message_model.dart';

/// Was in der Chatliste steht: wie viel ungelesen ist und seit wann.
typedef UngelesenStand = ({int anzahl, int hinweise, DateTime? ersteNeue});

/// Der Stand der Chatliste, aus dem gerechnet, was noch da ist.
///
/// Zaehler und Uhrzeit wurden bisher nur beim Eintreffen fortgeschrieben.
/// Verschwanden Nachrichten danach — ein Loeschtimer lief ab, die Gegenseite
/// warf ihren Chat weg —, blieben beide stehen. In der Liste stand dann
/// „3 neue" fuer einen Chat, in dem nichts mehr liegt.
///
/// Statt nachzurechnen, was abzuziehen waere, wird neu gezaehlt, was uebrig
/// ist. Das kann nicht auseinanderlaufen.
///
/// **Getrennt gezaehlt wird seit dem 02.09.2026.** Daniel: „es soll jede art
/// von nachrichten und sobald sie angekommen sind anzeigen." Ein
/// Screenshot-Hinweis tauchte in der Liste vorher gar nicht auf, wurde hier
/// aber mitgezaehlt — bei einer Neuberechnung sprang der Zaehler deshalb
/// rueckwirkend hoch. Jetzt gilt die Zahl echten Nachrichten und der Punkt
/// den Hinweisen.
abstract final class UnreadPolicy {
  /// Ungelesen ist, was die Gegenseite geschickt hat und was noch kein
  /// `readAt` traegt. Die Uhrzeit ist die des **aeltesten** davon — sie soll
  /// stehenbleiben, waehrend weitere hereinkommen.
  ///
  /// Getrennt nach Art: `anzahl` sind echte Nachrichten, `hinweise` sind
  /// Systemereignisse (Screenshot, Aufnahme, Fristwechsel, geloeschtes
  /// Konto). Eine passwortgeschuetzte Nachricht und eine mit eigenem
  /// Loeschtimer sind **echte Nachrichten** und gehoeren in `anzahl` —
  /// ausdruecklich so gewollt.
  ///
  /// Die Uhrzeit richtet sich nach beidem. Wer wissen will, seit wann etwas
  /// liegt, meint auch den Screenshot von heute morgen.
  static UngelesenStand zaehle(Iterable<Message> messages, String myId) {
    var anzahl = 0;
    var hinweise = 0;
    DateTime? erste;

    for (final m in messages) {
      // Was ich selbst getan habe, muss mir die Liste nicht melden.
      if (m.senderId == myId) continue;
      if (m.readAt != null) continue;

      if (m.isSystemEvent) {
        hinweise++;
      } else {
        anzahl++;
      }
      if (erste == null || m.timestamp.isBefore(erste)) erste = m.timestamp;
    }

    return (anzahl: anzahl, hinweise: hinweise, ersteNeue: erste);
  }

  /// Ob eine eintreffende Nachricht in diesem Moment schon als **gelesen**
  /// gilt.
  ///
  /// Die einzige Stelle, an der das entschieden wird — und die Antwort wandert
  /// sofort als `readAt` an die Nachricht. Bis zum 04.09.2026 gab es zwei
  /// Antworten auf dieselbe Frage: beim Eintreffen entschied der gerade
  /// offene Chat und setzte einen Zaehler hoch, beim Nachrechnen entschied
  /// `readAt`. Der offene Chat wird nirgends gespeichert; die beiden liefen
  /// auseinander, und der Zaehler sprang je nachdem, welche Stelle zuletzt
  /// lief. Ein Badge, das nach einem Neustart wiederkam, obwohl laengst
  /// gelesen war, kam von hier.
  ///
  /// Zwei Faelle gelten als gelesen:
  ///   * **Sie ist von mir.** Was ich selbst geschrieben habe, muss mir
  ///     niemand melden.
  ///   * **Der Chat liegt offen vor mir.** Dann steht sie in dem Moment auf
  ///     dem Bildschirm.
  ///
  /// [imVordergrund] gehoert zwingend dazu. Die Chat-Ansicht bleibt stehen,
  /// wenn die App weggewischt wird, und mit ihr die Angabe, welcher Chat
  /// offen ist. Ohne diese Frage verschluckte genau das die Meldung: eine
  /// Nachricht, die bei weggelegtem Geraet ankam, galt als gesehen.
  ///
  /// Steht als eigene Regel hier, weil der Provider Firebase braucht und
  /// darum nicht im Test laeuft. So ist wenigstens die Entscheidung geprueft.
  static bool beiZustellungGelesen({
    required String senderId,
    required String? eigeneId,
    required String chatId,
    required String? offenerChat,
    required bool imVordergrund,
  }) =>
      senderId == eigeneId || (imVordergrund && offenerChat == chatId);
}
