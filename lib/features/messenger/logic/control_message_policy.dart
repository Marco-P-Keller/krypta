/// Wie alt eine Kontrollnachricht sein darf, bevor sie verworfen wird.
///
/// Das Fenster lag pauschal bei fuenf Minuten — und was daran scheitert, wird
/// anschliessend **auch vom Server geloescht**. Damit waren `chatGone`,
/// `burned` und `unlock` wirkungslos, sobald die Gegenseite laenger als fuenf
/// Minuten offline war. Genau der Fall ist hier die Regel und nicht die
/// Ausnahme: die Gegenseite loescht abends den Chat, ich bin ueber Nacht
/// offline, und der ganze Fix verpufft.
///
/// Gegen Wiedereinspielen schuetzt ohnehin nicht das Alter, sondern der
/// **Zaehler** — streng steigend, pro Chat gespeichert, ueberlebt Neustarts.
/// Das Zeitfenster ist der Guertel neben dem Hosentraeger, und ein Guertel,
/// der die Hose runterzieht, taugt nichts.
///
/// Deshalb zwei Klassen: was einen **Zustand aendert**, muss ein langes
/// Offline ueberstehen. Was nur einen **Status anzeigt**, ist nach fuenf
/// Minuten ohnehin wertlos.
abstract final class ControlMessagePolicy {
  /// Das enge Fenster fuer reine Statusanzeigen.
  static const Duration kurz = Duration(minutes: 5);

  /// Das weite Fenster fuer Zustandsaenderungen.
  ///
  /// Dreissig Tage: laenger liegt ohnehin keine Nachricht auf dem Server, und
  /// der Zaehler traegt die eigentliche Last.
  static const Duration lang = Duration(days: 30);

  /// Arten, die einen Zustand aendern und deshalb ein Offline ueberleben
  /// muessen.
  static const Set<String> zustandsaendernd = {
    // Die Gegenseite hat den Chat weggeworfen — ohne diese Nachricht bleibt
    // die Verbindung fuer immer stumm.
    'chatGone',
    // Eine Nachricht mit Loeschtimer ist abgelaufen.
    'burned',
    // Eine passwortgeschuetzte Nachricht wurde entsperrt.
    'unlock',
    // Zuruecknehmen einer einzelnen Nachricht.
    'delete',
    // Die Gegenseite hat ihren Chat geleert.
    'clearMine',
    // Das Konto der Gegenseite gibt es nicht mehr.
    'gone',
    // Die Kontaktanfrage wurde angenommen.
    'accepted',
  };

  /// Wie alt eine Kontrollnachricht dieser Art sein darf.
  ///
  /// Fail-closed: was diese Fassung nicht kennt, bekommt das enge Fenster.
  static Duration maxAge(String type) =>
      zustandsaendernd.contains(type) ? lang : kurz;
}
