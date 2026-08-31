import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';

/// Die zwei Loeschtimer und wie sie sich vertragen.
///
/// **Der Timer einer einzelnen Nachricht** ist ein Versprechen an die
/// Gegenseite: er laeuft ab dem **Lesen** und raeumt auf beiden Geraeten auf.
///
/// **Der Chat-Timer** ist Hausordnung fuer diesen Chat: er laeuft ab dem
/// **Senden**, und wird er nachtraeglich eingeschaltet, gilt er auch fuer das,
/// was schon dasteht — dann ab dem Einschalten.
///
/// Hat eine Nachricht einen eigenen Timer, schlaegt der den Chat-Timer, in
/// beide Richtungen: laenger wie kuerzer.
void main() {
  final gesendet = DateTime(2026, 8, 31, 12, 0, 0);
  final gelesen = DateTime(2026, 8, 31, 12, 30, 0);

  Message nachricht({
    Duration? eigenerTimer,
    bool abSenden = false,
    DateTime? gelesenAm,
  }) =>
      Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: 'x',
        timestamp: gesendet,
        selfDestructDuration: eigenerTimer,
        selfDestructFromSend: abSenden,
        readAt: gelesenAm,
      );

  group('Eigener Timer — ab dem Lesen', () {
    test('vor dem Lesen laeuft nichts', () {
      expect(
        SelfDestructPolicy.expired(
          nachricht(eigenerTimer: const Duration(minutes: 10)),
          gesendet.add(const Duration(hours: 5)),
        ),
        isFalse,
      );
    });

    test('zehn Minuten nach dem Lesen ist sie faellig', () {
      final m = nachricht(
          eigenerTimer: const Duration(minutes: 10), gelesenAm: gelesen);
      expect(SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 9))),
          isFalse);
      expect(SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 11))),
          isTrue);
    });
  });

  group('Chat-Timer — ab dem Senden', () {
    test('eine neue Nachricht laeuft ab ihrem Sendezeitpunkt', () {
      // Nicht ab dem Lesen: der Chat-Timer ist Hausordnung, kein Versprechen.
      final m = nachricht(eigenerTimer: const Duration(minutes: 10), abSenden: true);
      expect(SelfDestructPolicy.expired(m, gesendet.add(const Duration(minutes: 9))),
          isFalse);
      expect(SelfDestructPolicy.expired(m, gesendet.add(const Duration(minutes: 11))),
          isTrue);
    });

    test('ungelesen laeuft sie trotzdem ab', () {
      expect(
        SelfDestructPolicy.expired(
          nachricht(eigenerTimer: const Duration(minutes: 10), abSenden: true),
          gesendet.add(const Duration(minutes: 11)),
        ),
        isTrue,
      );
    });
  });

  group('Nachtraeglich eingeschaltet', () {
    final eingeschaltet = DateTime(2026, 8, 31, 14, 0, 0);

    test('was schon dastand, bleibt ab dem Einschalten noch die volle Zeit', () {
      // Der eigentliche Punkt: eine Nachricht von 12 Uhr verschwindet nicht
      // sofort, wenn um 14 Uhr ein Zehn-Minuten-Timer eingeschaltet wird.
      final m = nachricht();
      expect(
        SelfDestructPolicy.expired(m, eingeschaltet.add(const Duration(minutes: 9)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: eingeschaltet),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(m, eingeschaltet.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });

    test('was danach kam, laeuft ab seinem eigenen Sendezeitpunkt', () {
      final spaeter = eingeschaltet.add(const Duration(hours: 1));
      final m = Message(
        id: 'm2',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: 'x',
        timestamp: spaeter,
      );
      expect(
        SelfDestructPolicy.expired(m, spaeter.add(const Duration(minutes: 9)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: eingeschaltet),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(m, spaeter.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });

    test('ohne Chat-Timer bleibt alles stehen', () {
      expect(
        SelfDestructPolicy.expired(
            nachricht(), gesendet.add(const Duration(days: 30))),
        isFalse,
      );
    });
  });

  group('Eigener Timer schlaegt den Chat-Timer', () {
    final eingeschaltet = DateTime(2026, 8, 31, 11, 0, 0);

    test('laenger: Chat 10 Min., Nachricht 24 Std. — sie bleibt 24 Std.', () {
      final m = nachricht(
          eigenerTimer: const Duration(hours: 24), gelesenAm: gelesen);
      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(hours: 23)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: eingeschaltet),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(hours: 25)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });

    test('kuerzer: Chat 24 Std., Nachricht 5 Min. — sie geht nach 5 Min.', () {
      final m = nachricht(
          eigenerTimer: const Duration(minutes: 5), gelesenAm: gelesen);
      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 6)),
            chatTimer: const Duration(hours: 24), chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });
  });

  group('Wer sagt Bescheid', () {
    test('nur der eigene, lesegebundene Timer wird gemeldet', () {
      // Ein Chat-Timer laeuft auf beiden Geraeten aus derselben Rechnung ab —
      // da ist nichts mitzuteilen. Nur beim lesegebundenen weiss allein der
      // Empfaenger, wann die Uhr abgelaufen ist.
      expect(
        SelfDestructPolicy.announceBurn(
            nachricht(eigenerTimer: const Duration(minutes: 10)), 'ich'),
        isTrue,
      );
      expect(
        SelfDestructPolicy.announceBurn(
            nachricht(eigenerTimer: const Duration(minutes: 10), abSenden: true),
            'ich'),
        isFalse,
      );
    });
  });

  group('Speichern und Laden', () {
    test('die Herkunft des Timers ueberlebt den Rundlauf', () {
      final m = nachricht(eigenerTimer: const Duration(minutes: 10), abSenden: true);
      expect(Message.fromMap(m.toMap()).selfDestructFromSend, isTrue);
    });

    test('ein Bestandsdatensatz gilt als lesegebunden', () {
      // Alles, was vor dieser Aenderung gespeichert wurde, lief ab dem Lesen.
      final alt = Message.fromMap({
        'id': 'm3',
        'chatId': 'c1',
        'senderId': 'marco',
        'recipientId': 'ich',
        'encryptedContent': 'x',
        'timestamp': gesendet.millisecondsSinceEpoch,
        'status': 0,
        'selfDestructMs': const Duration(minutes: 10).inMilliseconds,
      });
      expect(alt.selfDestructFromSend, isFalse);
    });
  });
}
