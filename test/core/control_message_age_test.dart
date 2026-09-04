import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/control_message_policy.dart';

/// Wie alt eine Kontrollnachricht sein darf, bevor sie verworfen wird.
///
/// Der Anlass: das Fenster lag pauschal bei fuenf Minuten, und danach wird die
/// Nachricht **auch vom Server geloescht**. Damit waren `chatGone`, `burned`
/// und `unlock` wirkungslos, sobald die Gegenseite laenger als fuenf Minuten
/// offline war — der Fall, der in diesem Projekt die Regel ist und nicht die
/// Ausnahme. Marco loescht abends den Chat, ich bin ueber Nacht offline: der
/// ganze Fix waere verpufft und die Verbindung wieder tot gewesen.
///
/// Der Ersatzschutz gegen Wiedereinspielen ist ohnehin nicht das Alter,
/// sondern der **Zaehler**: er ist streng steigend, wird pro Chat gespeichert
/// und ueberlebt Neustarts. Das Zeitfenster ist nur der Guertel neben dem
/// Hosentraeger.
///
/// Deshalb zwei Klassen. Was einen **Zustand aendert**, muss ein langes
/// Offline ueberleben. Was nur einen **Status anzeigt**, ist nach fuenf
/// Minuten ohnehin wertlos.
void main() {
  group('Zustandsaendernd — muss lange gelten', () {
    // `delivered` steht seit dem 04.09.2026 hier und nicht mehr bei der
    // reinen Anzeige: die Meldung traegt den **Zustellzeitpunkt**, und daran
    // haengt die Loeschfrist. Wird sie nach fuenf Minuten verworfen, faengt
    // die Uhr des Absenders nie an zu laufen — seine Fassung bliebe fuer
    // immer stehen, waehrend sie drueben verschwindet.
    for (final art in ['chatGone', 'burned', 'unlock', 'delete', 'clearMine',
      'gone', 'accepted', 'delivered']) {
      test('$art gilt auch nach einer Nacht offline', () {
        expect(
          ControlMessagePolicy.maxAge(art),
          greaterThan(const Duration(hours: 12)),
          reason: '$art aendert Zustand — ein Offline darf ihn nicht schlucken',
        );
      });
    }

    test('gedeckelt bei dreissig Tagen', () {
      // Laenger liegt ohnehin keine Nachricht auf dem Server.
      expect(ControlMessagePolicy.maxAge('chatGone'),
          const Duration(days: 30));
    });
  });

  group('Nur Anzeige — kurzes Fenster reicht', () {
    for (final art in ['read', 'screenshot', 'recording']) {
      test('$art bleibt bei fuenf Minuten', () {
        expect(ControlMessagePolicy.maxAge(art), const Duration(minutes: 5));
      });
    }
  });

  group('Unbekannte Art', () {
    test('faellt auf das kurze Fenster zurueck', () {
      // Fail-closed: was diese Fassung nicht kennt, bekommt das engere Fenster.
      expect(ControlMessagePolicy.maxAge('irgendwas'),
          const Duration(minutes: 5));
    });
  });
}
