import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';

/// Wann eine Nachricht mit Loeschtimer verschwindet — und bei wem.
///
/// Der Anlass: Daniel meldet, die Nachricht bleibt trotz abgelaufenem Timer
/// stehen. Die Uhr laeuft ab dem Lesen, und `readAt` setzt nur der Empfaenger.
/// Beim Absender bleibt es leer, solange keine Lesebestaetigung kommt — und
/// die ist standardmaessig aus. Seine Fassung lief also nie ab und blieb fuer
/// immer liegen. Eine App, die Vernichtung verspricht und nicht liefert, ist
/// schlimmer als eine ohne die Funktion.
void main() {
  final gelesen = DateTime(2026, 8, 31, 12, 0, 0);

  Message nachricht({
    Duration? timer,
    DateTime? gelesenAm,
    String von = 'marco',
  }) =>
      Message(
        id: 'm1',
        chatId: 'c1',
        senderId: von,
        recipientId: von == 'ich' ? 'marco' : 'ich',
        encryptedContent: 'x',
        timestamp: DateTime(2026, 8, 31, 11, 0),
        selfDestructDuration: timer,
        readAt: gelesenAm,
      );

  group('Abgelaufen', () {
    test('ohne Timer laeuft nichts ab', () {
      expect(
        SelfDestructPolicy.expired(
            nachricht(gelesenAm: gelesen), gelesen.add(const Duration(days: 1))),
        isFalse,
      );
    });

    test('ungelesen laeuft die Uhr trotzdem — sie startet bei der Zustellung',
        () {
      // Umgekehrt zum Stand von heute Mittag: der Timer einer einzelnen
      // Nachricht soll auch ablaufen, wenn sie nie geoeffnet wird.
      expect(
        SelfDestructPolicy.expired(
          nachricht(timer: const Duration(seconds: 30)),
          gelesen.add(const Duration(days: 1)),
        ),
        isTrue,
      );
    });

    test('vor Ablauf bleibt sie stehen', () {
      final m = nachricht(timer: const Duration(seconds: 30));
      expect(
        SelfDestructPolicy.expired(
            m, m.timestamp.add(const Duration(seconds: 29))),
        isFalse,
      );
    });

    test('nach Ablauf ist sie faellig', () {
      expect(
        SelfDestructPolicy.expired(
          nachricht(timer: const Duration(seconds: 30), gelesenAm: gelesen),
          gelesen.add(const Duration(seconds: 31)),
        ),
        isTrue,
      );
    });
  });

  group('Wer sagt Bescheid', () {
    test('der Empfaenger meldet den Ablauf', () {
      // Nur er hat `readAt` — nur er weiss, wann die Uhr abgelaufen ist.
      expect(
        SelfDestructPolicy.announceBurn(
            nachricht(timer: const Duration(seconds: 30), von: 'marco'), 'ich'),
        isTrue,
      );
    });

    test('der Absender meldet nichts', () {
      expect(
        SelfDestructPolicy.announceBurn(
            nachricht(timer: const Duration(seconds: 30), von: 'ich'), 'ich'),
        isFalse,
      );
    });

    test('ohne Timer wird nichts gemeldet', () {
      expect(
        SelfDestructPolicy.announceBurn(nachricht(von: 'marco'), 'ich'),
        isFalse,
      );
    });
  });

  group('Wie kurz eine fremde Frist sein darf', () {
    // Die Frist kommt aus der Nachricht der Gegenseite. Ohne Untergrenze
    // koennte sie eine Nachricht schicken, die nach einer Millisekunde
    // verschwindet — bei einem sendegebundenen Timer sogar, bevor ich sie
    // ueberhaupt gesehen habe. Ihre Nachricht zurueckzunehmen ist ihr Recht,
    // aber sie soll mir nicht die Gelegenheit zum Lesen stehlen koennen.

    test('null und negativ heisst: kein Timer', () {
      expect(SelfDestructPolicy.clampFremdeFrist(0), isNull);
      expect(SelfDestructPolicy.clampFremdeFrist(-5), isNull);
    });

    test('eine Millisekunde wird auf die Untergrenze angehoben', () {
      expect(SelfDestructPolicy.clampFremdeFrist(1),
          SelfDestructPolicy.mindestFrist);
    });

    test('die Untergrenze ist nicht laenger als eine halbe Minute', () {
      // Lang genug zum Lesen, kurz genug, um die Funktion nicht zu
      // entwerten.
      expect(SelfDestructPolicy.mindestFrist,
          lessThanOrEqualTo(const Duration(seconds: 30)));
      expect(SelfDestructPolicy.mindestFrist,
          greaterThanOrEqualTo(const Duration(seconds: 5)));
    });

    test('ein vernuenftiger Wert bleibt unveraendert', () {
      expect(SelfDestructPolicy.clampFremdeFrist(
              const Duration(minutes: 10).inMilliseconds),
          const Duration(minutes: 10));
    });

    test('gedeckelt bei dreissig Tagen', () {
      expect(SelfDestructPolicy.clampFremdeFrist(
              const Duration(days: 400).inMilliseconds),
          const Duration(days: 30));
    });
  });

  group('Burn after read zaehlt mit', () {
    // Auch eine Nachricht, die nach dem Lesen verbrennt, ist vergaenglich —
    // und auch bei ihr weiss nur der Empfaenger, wann es soweit ist.

    Message verbrennt({String von = 'marco'}) => Message(
          id: 'b1',
          chatId: 'c1',
          senderId: von,
          recipientId: von == 'ich' ? 'marco' : 'ich',
          encryptedContent: 'x',
          timestamp: DateTime(2026, 8, 31, 11, 0),
          burnAfterRead: true,
        );

    test('der Empfaenger meldet auch das Verbrennen', () {
      expect(SelfDestructPolicy.announceBurn(verbrennt(), 'ich'), isTrue);
    });

    test('meine eigene verbrennende Nachricht darf die Meldung raeumen', () {
      expect(SelfDestructPolicy.acceptBurn(verbrennt(von: 'ich'), 'ich'),
          isTrue);
    });

    test('eine ganz gewoehnliche Nachricht weiterhin nicht', () {
      final schlicht = Message(
        id: 'n1',
        chatId: 'c1',
        senderId: 'ich',
        recipientId: 'marco',
        encryptedContent: 'x',
        timestamp: DateTime(2026, 8, 31, 11, 0),
      );
      expect(SelfDestructPolicy.acceptBurn(schlicht, 'ich'), isFalse);
    });
  });

  group('Was eine Ablaufmeldung entfernen darf', () {
    test('meine eigene Nachricht mit Timer', () {
      expect(
        SelfDestructPolicy.acceptBurn(
            nachricht(timer: const Duration(seconds: 30), von: 'ich'), 'ich'),
        isTrue,
      );
    });

    test('meine Nachricht OHNE Timer nicht', () {
      // Sonst koennte die Gegenseite mit einer Ablaufmeldung beliebige
      // Nachrichten von meinem Geraet raeumen. Entfernt werden darf nur, was
      // ich selbst als vergaenglich markiert habe.
      expect(
        SelfDestructPolicy.acceptBurn(nachricht(von: 'ich'), 'ich'),
        isFalse,
      );
    });

    test('eine Nachricht der Gegenseite nicht', () {
      // Ihre eigene abzuraeumen ist Sache ihres eigenen Ablaufs, nicht meiner.
      expect(
        SelfDestructPolicy.acceptBurn(
            nachricht(timer: const Duration(seconds: 30), von: 'marco'), 'ich'),
        isFalse,
      );
    });
  });
}
