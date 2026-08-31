import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';

/// Die zwei Loeschtimer und wann ihre Uhr startet.
///
/// **Der Timer einer einzelnen Nachricht laeuft ab der Zustellung.** Nicht ab
/// dem Lesen: er soll auch ablaufen, wenn die Nachricht nie geoeffnet wird.
/// Stellt jemand dreissig Sekunden ein und der Empfaenger schaut erst nach
/// zwanzig hinein, bleiben ihm zehn.
///
/// **Der Chat-Timer laeuft ab dem Lesen.** Er ist Hausordnung, kein
/// Versprechen, und gilt auch fuer das, was schon dasteht — dann ab dem
/// Einschalten, damit nicht mit einem Tipp der halbe Verlauf verschwindet.
///
/// Ein eigener Timer der Nachricht schlaegt den Chat-Timer, in beide
/// Richtungen.
///
/// Auf dem Geraet des Empfaengers ist `timestamp` der **Zustellzeitpunkt** —
/// er wird beim Verarbeiten gesetzt. Beim Absender ist er der Sendezeitpunkt;
/// dessen Fassung raeumt deshalb nicht die eigene Uhr weg, sondern die
/// Ablaufmeldung der Gegenseite (siehe [SelfDestructPolicy.announceBurn]).
void main() {
  final zugestellt = DateTime(2026, 8, 31, 12, 0, 0);
  final gelesen = DateTime(2026, 8, 31, 12, 0, 20);

  Message nachricht({
    Duration? timer,
    bool vomChat = false,
    DateTime? gelesenAm,
  }) =>
      Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: 'x',
        timestamp: zugestellt,
        selfDestructDuration: timer,
        selfDestructFromChat: vomChat,
        readAt: gelesenAm,
      );

  group('Eigener Timer — ab der Zustellung', () {
    test('dreissig Sekunden nach der Zustellung ist sie faellig', () {
      final m = nachricht(timer: const Duration(seconds: 30));
      expect(
          SelfDestructPolicy.expired(
              m, zugestellt.add(const Duration(seconds: 29))),
          isFalse);
      expect(
          SelfDestructPolicy.expired(
              m, zugestellt.add(const Duration(seconds: 31))),
          isTrue);
    });

    test('sie laeuft auch ab, wenn sie nie gelesen wurde', () {
      // Der Kern des Punktes: Ungelesenes bleibt nicht liegen.
      expect(
        SelfDestructPolicy.expired(nachricht(timer: const Duration(seconds: 30)),
            zugestellt.add(const Duration(minutes: 5))),
        isTrue,
      );
    });

    test('spaeter Lesen verlaengert nichts', () {
      // Nach zwanzig Sekunden geoeffnet: es bleiben zehn, nicht dreissig.
      final m = nachricht(
          timer: const Duration(seconds: 30), gelesenAm: gelesen);
      expect(
          SelfDestructPolicy.expired(
              m, zugestellt.add(const Duration(seconds: 31))),
          isTrue);
    });
  });

  group('Chat-Timer — ab dem Lesen', () {
    final eingeschaltet = DateTime(2026, 8, 31, 11, 0, 0);

    test('ungelesen laeuft er nicht', () {
      expect(
        SelfDestructPolicy.expired(
            nachricht(), zugestellt.add(const Duration(days: 365)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isFalse,
      );
    });

    test('gelesen laeuft er ab dem Lesen', () {
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

    test('nachtraeglich eingeschaltet: volle Frist ab dem Einschalten', () {
      final spaeter = DateTime(2026, 8, 31, 14, 0, 0);
      final m = nachricht(gelesenAm: gelesen);
      expect(
        SelfDestructPolicy.expired(m, spaeter.add(const Duration(minutes: 9)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: spaeter),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(m, spaeter.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: spaeter),
        isTrue,
      );
    });

    test('eine Nachricht MIT Chat-Frist laeuft ebenfalls ab dem Lesen', () {
      // Die Frist reist mit, damit beide Seiten sie kennen — die Herkunft auch,
      // sonst wuerde sie beim Empfaenger als eigener Timer ab Zustellung laufen.
      final m = nachricht(timer: const Duration(minutes: 10), vomChat: true);
      expect(
        SelfDestructPolicy.expired(m, zugestellt.add(const Duration(hours: 5))),
        isFalse,
        reason: 'ungelesen laeuft der Chat-Timer nicht',
      );
    });
  });

  group('Eigener Timer schlaegt den Chat-Timer', () {
    final eingeschaltet = DateTime(2026, 8, 31, 11, 0, 0);

    test('laenger', () {
      final m = nachricht(timer: const Duration(hours: 24));
      expect(
        SelfDestructPolicy.expired(m, zugestellt.add(const Duration(hours: 23)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isFalse,
      );
    });

    test('kuerzer', () {
      final m = nachricht(timer: const Duration(minutes: 5));
      expect(
        SelfDestructPolicy.expired(m, zugestellt.add(const Duration(minutes: 6)),
            chatTimer: const Duration(hours: 24),
            chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });
  });

  group('Speichern und Laden', () {
    test('die Herkunft des Timers ueberlebt den Rundlauf', () {
      final m = nachricht(timer: const Duration(minutes: 10), vomChat: true);
      expect(Message.fromMap(m.toMap()).selfDestructFromChat, isTrue);
    });

    test('ein Bestandsdatensatz gilt als eigener Timer', () {
      final alt = Message.fromMap({
        'id': 'm3',
        'chatId': 'c1',
        'senderId': 'marco',
        'recipientId': 'ich',
        'encryptedContent': 'x',
        'timestamp': zugestellt.millisecondsSinceEpoch,
        'status': 0,
        'selfDestructMs': const Duration(minutes: 10).inMilliseconds,
      });
      expect(alt.selfDestructFromChat, isFalse);
    });
  });
}
