import 'package:flutter/widgets.dart';

/// Wann der Inbox-Listener abgebaut und wann er wieder angehängt wird.
///
/// Bisher lief er beim Wechsel in den Hintergrund einfach weiter. Die
/// Verbindung riss trotzdem — das Betriebssystem friert den Prozess ein —,
/// nur merkte das niemand: der Wiederanlauf blieb einem Timer überlassen, der
/// nichts vom Aufwachen weiß. Eine Kontaktanfrage vom Vormittag lag deshalb
/// nach dem Öffnen noch eine Minute herum, obwohl die Chatliste längst stand.
///
/// Mit dieser Regel ist das Aufwachen der eine, klar definierte
/// Einstiegspunkt: im Hintergrund wird sauber abgebaut, beim Aufwachen frisch
/// angehängt.
abstract final class SyncLifecyclePolicy {
  /// Ob in diesem Zustand abzubauen ist.
  ///
  /// `detached` gehört dazu: die App wird abgeräumt, ein Listener hat dort
  /// nichts mehr verloren.
  static bool shouldPause(AppLifecycleState state) => switch (state) {
        AppLifecycleState.paused ||
        AppLifecycleState.hidden ||
        AppLifecycleState.detached =>
          true,
        // `inactive` feuert bei jedem flüchtigen Griff — Screenshot,
        // Berechtigungsabfrage, Kontrollzentrum, eingehender Anruf. Würde das
        // abbauen, kostete jeder davon eine Zustellung.
        AppLifecycleState.inactive || AppLifecycleState.resumed => false,
      };

  /// Ob in diesem Zustand wieder anzuhängen ist.
  static bool shouldResume(AppLifecycleState state) =>
      state == AppLifecycleState.resumed;
}
