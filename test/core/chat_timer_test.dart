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

  group('Chat-Timer — ab der Zustellung', () {
    // Geaendert am 02.09.2026 auf Daniels Ansage: der Countdown beginnt mit
    // der Zustellung, nicht mehr mit dem Lesen. Sein Beispiel: Frist zehn
    // Minuten, Zustellung um 18:00, geloescht um 18:10, egal ob geoeffnet.
    //
    // Damit verschwindet auch Ungelesenes. Das war bis zum 01.09. bewusst
    // andersherum; die Umkehr ist seine Entscheidung.
    final eingeschaltet = DateTime(2026, 8, 31, 11, 0, 0);

    test('ungelesen laeuft er jetzt trotzdem ab', () {
      expect(
        SelfDestructPolicy.expired(
            nachricht(), zugestellt.add(const Duration(minutes: 9)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(
            nachricht(), zugestellt.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isTrue,
        reason: 'ungelesen darf ihn nicht mehr aufhalten',
      );
    });

    test('spaeteres Lesen verschiebt nichts', () {
      // Wer erst nach neun Minuten hineinschaut, hat noch eine.
      final m = nachricht(gelesenAm: zugestellt.add(const Duration(minutes: 9)));
      expect(
        SelfDestructPolicy.expired(m, zugestellt.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10),
            chatTimerSetAt: eingeschaltet),
        isTrue,
      );
    });

    test('nachtraeglich eingeschaltet raeumt nicht sofort den Verlauf', () {
      // Ohne diese Regel waeren beim Einschalten alle aelteren Nachrichten
      // im selben Moment ueberfaellig und der ganze sichtbare Verlauf waere
      // mit einem Tipp weg. Daniels Entscheidung vom 31.08., sie gilt weiter.
      final spaeter = DateTime(2026, 8, 31, 14, 0, 0);
      final m = nachricht();
      expect(
        SelfDestructPolicy.expired(m, spaeter.add(const Duration(minutes: 9)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: spaeter),
        isFalse,
        reason: 'volle Frist ab dem Einschalten, nicht sofort',
      );
      expect(
        SelfDestructPolicy.expired(m, spaeter.add(const Duration(minutes: 11)),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: spaeter),
        isTrue,
      );
    });

    test('eine Nachricht MIT mitgereister Chat-Frist laeuft ab Zustellung', () {
      final m = nachricht(timer: const Duration(minutes: 10), vomChat: true);
      expect(
        SelfDestructPolicy.expired(m, zugestellt.add(const Duration(minutes: 9))),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(m, zugestellt.add(const Duration(minutes: 11))),
        isTrue,
        reason: 'die Herkunft der Frist aendert den Start nicht mehr',
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
