import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';

/// Woran der Loeschtimer haengt: am **Zustellzeitpunkt**, und der ist auf
/// beiden Geraeten derselbe.
///
/// Der Anlass: Daniel meldet am 04.09.2026, dass der Chat-Timer nicht
/// zuverlaessig loescht. Die Ursache lag nicht im Zaehlen, sondern im
/// Startpunkt. Gerechnet wurde ab `timestamp`, und der bedeutet auf den
/// beiden Geraeten Verschiedenes: beim Empfaenger der Moment des Abholens,
/// beim Absender der des Sendens. Wartet eine Nachricht eine Stunde auf dem
/// Server, lief die Fassung des Absenders eine Stunde frueher ab als die des
/// Empfaengers — bei fuenf Minuten Frist war sie bei ihm weg, bevor die
/// andere Seite sie ueberhaupt hatte.
///
/// Jetzt traegt jede Nachricht ihren Zustellzeitpunkt selbst. Der Empfaenger
/// setzt ihn beim Abholen, der Absender uebernimmt ihn aus der
/// Zustellbestaetigung — die seit dem 04.09.2026 immer kommt.
void main() {
  final gesendet = DateTime(2026, 9, 4, 11, 0, 0);
  final zugestellt = DateTime(2026, 9, 4, 12, 0, 0);

  Message nachricht({
    Duration? timer,
    bool vomChat = false,
    DateTime? zugestelltAm,
    String von = 'marco',
  }) =>
      Message(
        id: 'm1',
        chatId: 'c1',
        senderId: von,
        recipientId: von == 'ich' ? 'marco' : 'ich',
        encryptedContent: 'x',
        timestamp: gesendet,
        deliveredAt: zugestelltAm,
        selfDestructDuration: timer,
        selfDestructFromChat: vomChat,
      );

  group('Der Start der Uhr', () {
    test('ohne Zustellung laeuft keine Uhr', () {
      // Eine Nachricht, die noch auf dem Server liegt, darf beim Absender
      // nicht ablaufen. Sonst loescht er, was die Gegenseite nie gesehen hat.
      expect(
        SelfDestructPolicy.expired(
          nachricht(timer: const Duration(minutes: 5)),
          gesendet.add(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('die Uhr startet bei der Zustellung, nicht beim Senden', () {
      final m =
          nachricht(timer: const Duration(minutes: 5), zugestelltAm: zugestellt);
      expect(
        SelfDestructPolicy.expired(m, gesendet.add(const Duration(minutes: 6))),
        isFalse,
        reason: 'eine Stunde nach dem Senden, aber noch nicht zugestellt+5',
      );
      expect(
        SelfDestructPolicy.expired(
            m, zugestellt.add(const Duration(minutes: 4))),
        isFalse,
      );
      expect(
        SelfDestructPolicy.expired(
            m, zugestellt.add(const Duration(minutes: 6))),
        isTrue,
      );
    });

    test('beide Geraete kommen auf denselben Loeschzeitpunkt', () {
      // Der eigentliche Punkt. Die beiden Fassungen einer Nachricht tragen
      // verschiedene `timestamp` — Senden hier, Abholen dort — aber denselben
      // Zustellzeitpunkt.
      final beimAbsender = Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'ich',
        recipientId: 'marco',
        encryptedContent: 'x',
        timestamp: gesendet,
        deliveredAt: zugestellt,
        selfDestructDuration: const Duration(minutes: 5),
      );
      final beimEmpfaenger = beimAbsender.copyWith();
      final empfaengerFassung = Message.fromMap({
        ...beimEmpfaenger.toMap(),
        'timestamp': zugestellt.millisecondsSinceEpoch,
      });

      expect(
        SelfDestructPolicy.deadline(empfaengerFassung),
        SelfDestructPolicy.deadline(beimAbsender),
      );
      expect(SelfDestructPolicy.deadline(beimAbsender),
          zugestellt.add(const Duration(minutes: 5)));
    });

    test('der Zustellzeitpunkt ueberlebt den Rundlauf ueber die Platte', () {
      final m =
          nachricht(timer: const Duration(minutes: 5), zugestelltAm: zugestellt);
      expect(Message.fromMap(m.toMap()).deliveredAt, zugestellt);
    });
  });

  group('Die gemeldete Zustellung der Gegenseite', () {
    // Der Absender erfaehrt den Zeitpunkt aus einer Kontrollnachricht. Sie
    // ist signiert, aber sie kommt von einer fremden Uhr — und eine fremde
    // Uhr darf meine Frist nicht verbiegen.
    test('eine plausible Meldung gilt', () {
      expect(
        SelfDestructPolicy.zustellzeitpunkt(
          gemeldet: zugestellt,
          gesendet: gesendet,
          jetzt: zugestellt.add(const Duration(seconds: 30)),
        ),
        zugestellt,
      );
    });

    test('nie vor dem Senden', () {
      // Eine zurueckgestellte Uhr drueben wuerde die Nachricht sonst
      // rueckwirkend abgelaufen machen.
      expect(
        SelfDestructPolicy.zustellzeitpunkt(
          gemeldet: gesendet.subtract(const Duration(hours: 3)),
          gesendet: gesendet,
          jetzt: zugestellt,
        ),
        gesendet,
      );
    });

    test('nie in der Zukunft', () {
      // Eine vorgestellte Uhr drueben wuerde die Nachricht sonst nie
      // ablaufen lassen.
      expect(
        SelfDestructPolicy.zustellzeitpunkt(
          gemeldet: zugestellt.add(const Duration(days: 2)),
          gesendet: gesendet,
          jetzt: zugestellt,
        ),
        zugestellt,
      );
    });
  });

  group('Bestand ohne Zustellzeitpunkt', () {
    Message bestand({
      required String von,
      MessageStatus status = MessageStatus.sent,
      DateTime? zugestelltAm,
    }) =>
        Message(
          id: 'm1',
          chatId: 'c1',
          senderId: von,
          recipientId: von == 'ich' ? 'marco' : 'ich',
          encryptedContent: 'x',
          timestamp: gesendet,
          deliveredAt: zugestelltAm,
          status: status,
          selfDestructDuration: const Duration(minutes: 5),
        );

    test('was bei mir liegt und von drueben kam, war zugestellt', () {
      // Sonst laege aller Bestand fuer immer da: ohne Zustellzeitpunkt laeuft
      // keine Uhr. Dass ich sie habe, ist der Nachweis der Zustellung; der
      // Sendezeitpunkt ist die beste Schaetzung, die davon noch da ist.
      final liste = [bestand(von: 'marco')];
      expect(SelfDestructPolicy.zustellungNachtragen(liste, 'ich'), isTrue);
      expect(liste[0].deliveredAt, gesendet);
    });

    test('meine eigene, deren Zustellung gemeldet war, ebenfalls', () {
      final liste = [bestand(von: 'ich', status: MessageStatus.delivered)];
      expect(SelfDestructPolicy.zustellungNachtragen(liste, 'ich'), isTrue);
      expect(liste[0].deliveredAt, gesendet);
    });

    test('meine eigene, noch nicht zugestellte, bleibt ohne', () {
      // Der eigentliche Grund fuer die Unterscheidung: sonst bekaeme der
      // Postausgang bei jedem Start einen erfundenen Zustellzeitpunkt und
      // liefe ab, ohne dass die Nachricht je angekommen waere.
      final liste = [bestand(von: 'ich')];
      expect(SelfDestructPolicy.zustellungNachtragen(liste, 'ich'), isFalse);
      expect(liste[0].deliveredAt, isNull);
    });

    test('ein vorhandener Zeitpunkt wird nicht ueberschrieben', () {
      final liste = [bestand(von: 'marco', zugestelltAm: zugestellt)];
      expect(SelfDestructPolicy.zustellungNachtragen(liste, 'ich'), isFalse);
      expect(liste[0].deliveredAt, zugestellt);
    });
  });

  group('Welche Frist gilt', () {
    final eingeschaltet = DateTime(2026, 9, 4, 10, 0, 0);

    test('eine Chat-Frist folgt der aktuellen Einstellung des Chats', () {
      // Die Einstellung gehoert dem Chat und wird zwischen beiden Seiten
      // abgeglichen. Waere die mitgereiste Zahl massgeblich, liefe nach einer
      // Aenderung jede Seite mit dem, was zufaellig in ihren alten
      // Nachrichten steht.
      final m = nachricht(
          timer: const Duration(minutes: 5),
          vomChat: true,
          zugestelltAm: zugestellt);
      expect(
        SelfDestructPolicy.deadline(m,
            chatTimer: const Duration(hours: 1),
            chatTimerSetAt: eingeschaltet),
        zugestellt.add(const Duration(hours: 1)),
      );
    });

    test('ohne Einstellung bleibt die mitgereiste Frist', () {
      // Fail-closed: geht die Meldung ueber die neue Einstellung verloren,
      // wird die Nachricht nach der Frist geloescht, die ihr mitgegeben
      // wurde — nicht gar nicht.
      final m = nachricht(
          timer: const Duration(minutes: 5),
          vomChat: true,
          zugestelltAm: zugestellt);
      expect(SelfDestructPolicy.deadline(m),
          zugestellt.add(const Duration(minutes: 5)));
    });

    test('ein eigener Timer der Nachricht folgt dem Chat nicht', () {
      // Bestand und fremde Absender: was eine eigene Frist traegt, behaelt
      // sie. Der Absender hat sie dieser einen Nachricht mitgegeben.
      final m = nachricht(
          timer: const Duration(minutes: 5), zugestelltAm: zugestellt);
      expect(
        SelfDestructPolicy.deadline(m, chatTimer: const Duration(hours: 1)),
        zugestellt.add(const Duration(minutes: 5)),
      );
    });

    test('der nachtraeglich eingeschaltete Chat-Timer schiebt den Start', () {
      // Daniels Regel vom 31.08., sie gilt weiter: sonst waere beim Umlegen
      // des Schalters der halbe Verlauf im selben Moment ueberfaellig.
      final spaeter = zugestellt.add(const Duration(hours: 2));
      expect(
        SelfDestructPolicy.deadline(nachricht(zugestelltAm: zugestellt),
            chatTimer: const Duration(minutes: 10), chatTimerSetAt: spaeter),
        spaeter.add(const Duration(minutes: 10)),
      );
    });
  });
}
