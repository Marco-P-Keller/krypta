/// Was mit **einer** Nachricht geschehen soll.
///
/// Vier Faelle, und sie schliessen einander aus. Drei davon waehlt der
/// Absender fuer diese eine Nachricht; der vierte ist die Regel des Chats und
/// gilt, solange er nichts anderes waehlt.
///
/// Am 02.09.2026 waren daraus drei Konzepte eines geworden: nur noch die
/// einmalige Nachricht, alles andere unter der Frist des Chats. Daniels Liste
/// vom 22.09. unterscheidet wieder vier Faelle, und sie sind nicht dasselbe:
///
///   1. Der Selbstlösch-Timer für den **gesamten Chat**.
///   2. Derselbe Timer für **einzelne Nachrichten**.
///   3. **Nach Ansehen löschen**, für einzelne Nachrichten oder den Chat.
///   4. Die Nachricht zur **einmaligen Ansicht**.
enum Nachrichtenregel {
  /// Was der Chat vorgibt — eine Frist, „direkt nach dem Lesen", oder nichts.
  chatregel,

  /// Eine Frist nur fuer diese Nachricht, ab Zustellung.
  frist,

  /// Gelesen und Chat verlassen: weg. Keine Uhr.
  nachAnsehen,

  /// Einmal zu oeffnen, dann verbraucht.
  einmalig,
}

/// Was beim Senden an der Nachricht haengt.
typedef Sendeauftrag = ({
  Duration? frist,
  bool vomChat,
  bool nachAnsehen,
  bool einmalig,
});

abstract final class RegelPolicy {
  /// Die gewaehlte Regel in das uebersetzen, was `sendMessage` braucht.
  ///
  /// Steht hier und nicht in der Chat-Ansicht, weil es eine Regel ist und
  /// keine Darstellung — und weil eine Ansicht mit Provider und Firebase
  /// nicht im Test laeuft. Dieselbe Hausregel wie bei UnreadPolicy und
  /// SelfDestructPolicy.
  ///
  /// Die **Herkunft** der Frist ist der Teil, den man leicht uebersieht: eine
  /// Chat-Frist folgt spaeter der aktuellen Einstellung des Chats, weil sie
  /// beiden Seiten gehoert und zwischen ihnen abgeglichen wird; eine eigene
  /// behaelt die Nachricht. Siehe SelfDestructPolicy.deadline. Vor dem
  /// 22.09.2026 ging jede Nachricht mit `selfDestructFromChat: true` raus —
  /// es gab ja nur die eine Quelle.
  static Sendeauftrag auftrag({
    required Nachrichtenregel regel,
    Duration? einzelFrist,
    Duration? chatFrist,
  }) {
    switch (regel) {
      case Nachrichtenregel.chatregel:
        return (
          frist: chatFrist,
          vomChat: true,
          nachAnsehen: false,
          einmalig: false
        );
      case Nachrichtenregel.frist:
        // Ohne gewaehlte Dauer waere „eigene Frist" eine Zusage ohne Inhalt.
        // Dann gilt wieder der Chat — nicht „gar keine Frist", denn das waere
        // stillschweigend weniger, als der Chat verspricht.
        if (einzelFrist == null) {
          return (
            frist: chatFrist,
            vomChat: true,
            nachAnsehen: false,
            einmalig: false
          );
        }
        return (
          frist: einzelFrist,
          vomChat: false,
          nachAnsehen: false,
          einmalig: false
        );
      case Nachrichtenregel.nachAnsehen:
        // Keine Uhr, sondern ein Ereignis. Auch **nicht** die des Chats: wer
        // „nach Ansehen" waehlt, hat fuer diese Nachricht entschieden, und
        // eine zusaetzlich mitlaufende Frist waere eine zweite Zusage.
        return (
          frist: null,
          vomChat: false,
          nachAnsehen: true,
          einmalig: false
        );
      case Nachrichtenregel.einmalig:
        // Sie geht mit dem Oeffnen. Eine Frist daneben hat sie am 07.09.2026
        // schon einmal ungeoeffnet verschwinden lassen — siehe
        // SelfDestructPolicy.deadline.
        return (
          frist: null,
          vomChat: false,
          nachAnsehen: false,
          einmalig: true
        );
    }
  }
}
