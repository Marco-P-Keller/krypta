import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/inbox_reconnect_backoff.dart';

/// Wie lange der Inbox-Listener nach einem Abriss wartet, bevor er es erneut
/// versucht.
///
/// Der Anlass: eine Kontaktanfrage lag seit dem Vormittag auf dem Server und
/// erschien erst rund eine Minute nach dem Öffnen der App. Die Chatliste war
/// sofort da — der Listener hing nur noch nicht wieder dran. Die Treppe war
/// über Nacht auf ihren Deckel geklettert und wurde nie zurückgesetzt, also
/// kostete der erste fehlgeschlagene Versuch nach dem Aufwachen eine volle
/// Minute Stille.
void main() {
  group('Treppe nach oben', () {
    test('der erste Fehlversuch wartet eine Sekunde', () {
      final backoff = InboxReconnectBackoff();
      expect(backoff.nachFehlversuch(), const Duration(seconds: 1));
    });

    test('jeder weitere Fehlversuch verdoppelt die Wartezeit', () {
      final backoff = InboxReconnectBackoff();
      final gewartet = [
        for (var i = 0; i < 6; i++) backoff.nachFehlversuch().inSeconds,
      ];
      expect(gewartet, [1, 2, 4, 8, 16, 32]);
    });

    test('die Wartezeit ist bei einer Minute gedeckelt', () {
      final backoff = InboxReconnectBackoff();
      for (var i = 0; i < 6; i++) {
        backoff.nachFehlversuch();
      }
      expect(backoff.nachFehlversuch(), InboxReconnectBackoff.deckel);
      expect(backoff.nachFehlversuch(), InboxReconnectBackoff.deckel);
      expect(InboxReconnectBackoff.deckel, const Duration(seconds: 60));
    });
  });

  group('Zuruecksetzen', () {
    test('ein angekommener Snapshot setzt die Treppe zurueck', () {
      final backoff = InboxReconnectBackoff();
      for (var i = 0; i < 10; i++) {
        backoff.nachFehlversuch();
      }

      backoff.angekommen();

      expect(backoff.nachFehlversuch(), const Duration(seconds: 1));
    });

    test('nach dem Zuruecksetzen faengt die Treppe wieder von vorne an', () {
      final backoff = InboxReconnectBackoff();
      for (var i = 0; i < 10; i++) {
        backoff.nachFehlversuch();
      }

      backoff.angekommen();

      final gewartet = [
        for (var i = 0; i < 4; i++) backoff.nachFehlversuch().inSeconds,
      ];
      expect(gewartet, [1, 2, 4, 8]);
    });

    test('ohne Fehlversuch dazwischen bleibt Zuruecksetzen folgenlos', () {
      final backoff = InboxReconnectBackoff();
      backoff.angekommen();
      expect(backoff.nachFehlversuch(), const Duration(seconds: 1));
    });
  });
}
