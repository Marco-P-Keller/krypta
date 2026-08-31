import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';

/// Die zwei Loeschtimer und wie sie sich vertragen.
///
/// **Beide laufen ab dem Lesen.** Ein Timer, der abliefe, bevor die Nachricht
/// ueberhaupt jemand gesehen hat, haette sie nie zugestellt — das gilt fuer
/// den Timer einer einzelnen Nachricht wie fuer den des ganzen Chats.
///
/// Der Preis, offen benannt: **Ungelesenes laeuft nie ab.** Ein Chat mit
/// 24-Stunden-Regel raeumt nichts weg, was niemand geoeffnet hat. Das war
/// Daniels Entscheidung am 31.08., nachdem der Chat-Timer einen Tag lang ab
/// dem Senden lief.
///
/// Der Unterschied zwischen den beiden liegt woanders: der Chat-Timer gilt
/// auch fuer das, was schon dasteht — dann ab dem **Einschalten**, damit nicht
/// mit einem Tipp der halbe Verlauf im selben Moment verschwindet. Und ein
/// eigener Timer der Nachricht schlaegt ihn, in beide Richtungen.
void main() {
  final gesendet = DateTime(2026, 8, 31, 12, 0, 0);
  final gelesen = DateTime(2026, 8, 31, 12, 30, 0);

  Message nachricht({Duration? eigenerTimer, DateTime? gelesenAm}) => Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: 'x',
        timestamp: gesendet,
        selfDestructDuration: eigenerTimer,
        readAt: gelesenAm,
      );

  group('Eigener Timer', () {
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
      expect(
          SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 9))),
          isFalse);
      expect(
          SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 11))),
          isTrue);
    });
  });

  group('Chat-Timer', () {
    final eingeschaltet = DateTime(2026, 8, 31, 11, 0, 0);

    test('laeuft ebenfalls ab dem Lesen', () {
      final m = nachricht(gelesenAm: gelesen);
      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 9)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });

    test('Ungelesenes laeuft nie ab', () {
      // Der Preis der Entscheidung, und er gehoert festgehalten: ein Chat mit
      // Frist raeumt nichts weg, was niemand geoeffnet hat.
      expect(
        SelfDestructPolicy.expired(nachricht(), gesendet.add(const Duration(days: 365)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isFalse,
      );
    });

    test('ohne Chat-Timer bleibt alles stehen', () {
      expect(
        SelfDestructPolicy.expired(
            nachricht(gelesenAm: gelesen), gelesen.add(const Duration(days: 30))),
        isFalse,
      );
    });
  });

  group('Nachtraeglich eingeschaltet', () {
    test('laenger Gelesenes bekommt die volle Frist ab dem Einschalten', () {
      // Gelesen um 12:30, Timer erst um 14:00 eingeschaltet: die Nachricht
      // darf nicht im selben Moment verschwinden.
      final eingeschaltet = DateTime(2026, 8, 31, 14, 0, 0);
      final m = nachricht(gelesenAm: gelesen);

      expect(
        SelfDestructPolicy.expired(
            m, eingeschaltet.add(const Duration(minutes: 9)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(
            m, eingeschaltet.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });

    test('spaeter Gelesenes laeuft ab seinem eigenen Lesezeitpunkt', () {
      final eingeschaltet = DateTime(2026, 8, 31, 11, 0, 0);
      final m = nachricht(gelesenAm: gelesen);

      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });
  });

  group('Eigener Timer schlaegt den Chat-Timer', () {
    final eingeschaltet = DateTime(2026, 8, 31, 11, 0, 0);

    test('laenger: Chat 10 Min., Nachricht 24 Std. — sie bleibt 24 Std.', () {
      final m =
          nachricht(eigenerTimer: const Duration(hours: 24), gelesenAm: gelesen);
      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(hours: 23)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(hours: 25)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });

    test('kuerzer: Chat 24 Std., Nachricht 5 Min. — sie geht nach 5 Min.', () {
      final m =
          nachricht(eigenerTimer: const Duration(minutes: 5), gelesenAm: gelesen);
      expect(
        SelfDestructPolicy.expired(m, gelesen.add(const Duration(minutes: 6)),
            chatTimer: const Duration(hours: 24),
            chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });
  });

  group('Wer sagt Bescheid', () {
    test('der Empfaenger meldet jeden Ablauf, den nur er kennen kann', () {
      // Beide Timer haengen jetzt am Lesen, und `readAt` hat nur der
      // Empfaenger. Also meldet er beide.
      expect(
        SelfDestructPolicy.announceBurn(
            nachricht(eigenerTimer: const Duration(minutes: 10)), 'ich'),
        isTrue,
      );
    });
  });
}
