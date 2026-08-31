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

    test('ungelesen laeuft die Uhr nicht — sie startet beim Lesen', () {
      expect(
        SelfDestructPolicy.expired(
          nachricht(timer: const Duration(seconds: 30)),
          gelesen.add(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('vor Ablauf bleibt sie stehen', () {
      expect(
        SelfDestructPolicy.expired(
          nachricht(timer: const Duration(seconds: 30), gelesenAm: gelesen),
          gelesen.add(const Duration(seconds: 29)),
        ),
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
