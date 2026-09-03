import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/contact_model.dart';
import 'package:kryptaapp/features/messenger/logic/gone_policy.dart';

/// Wie lange ein geloeschtes Konto noch stehen bleibt und ab wann gerechnet
/// wird.
///
/// Der Kern: gerechnet wird ab der **Loeschung**, nicht ab dem Moment, in dem
/// die Meldung gelesen wird. Sonst haette jeder Empfaenger eine andere Frist,
/// und wer eine Nacht offline war, bekaeme den Kontakt noch einmal einen
/// vollen Tag vorgesetzt.
Contact _kontakt({
  bool isGone = false,
  DateTime? goneAt,
  String id = 'marco',
}) =>
    Contact(
      id: id,
      displayName: 'Marco',
      publicKey: Uint8List(32),
      addedAt: DateTime(2026, 9, 1),
      isGone: isGone,
      goneAt: goneAt,
    );

void main() {
  final jetzt = DateTime(2026, 9, 3, 12, 0);

  group('loeschzeitpunkt', () {
    test('nimmt den gemeldeten Zeitpunkt, nicht den des Lesens', () {
      final geloescht = DateTime(2026, 9, 3, 2, 0);
      expect(
        GonePolicy.loeschzeitpunkt(geloescht.millisecondsSinceEpoch, jetzt),
        geloescht,
      );
    });

    test('ein Zeitstempel in der Zukunft wird auf jetzt geklemmt', () {
      // Sonst liesse eine boesartige Gegenseite ihren Eintrag beliebig lange
      // stehen: Zeitstempel ein Jahr voraus, Frist laeuft nie ab.
      final zukunft = jetzt.add(const Duration(days: 365));
      expect(
        GonePolicy.loeschzeitpunkt(zukunft.millisecondsSinceEpoch, jetzt),
        jetzt,
      );
    });

    test('ein alter Zeitstempel wird NICHT angehoben', () {
      // Eine Meldung, die zwei Tage auf dem Weg war, soll sofort abraeumen
      // und nicht noch einmal einen Tag laufen.
      final alt = jetzt.subtract(const Duration(days: 2));
      final zeitpunkt =
          GonePolicy.loeschzeitpunkt(alt.millisecondsSinceEpoch, jetzt);
      expect(zeitpunkt, alt);
      expect(
        GonePolicy.abgelaufen(_kontakt(isGone: true, goneAt: zeitpunkt), jetzt),
        isTrue,
      );
    });
  });

  group('abgelaufen', () {
    test('vor Ablauf der 24 Stunden bleibt der Kontakt stehen', () {
      final vorEinerStunde = jetzt.subtract(const Duration(hours: 1));
      expect(
        GonePolicy.abgelaufen(
            _kontakt(isGone: true, goneAt: vorEinerStunde), jetzt),
        isFalse,
      );
    });

    test('eine Minute vor Ablauf noch nicht', () {
      final knapp =
          jetzt.subtract(const Duration(hours: 23, minutes: 59));
      expect(
        GonePolicy.abgelaufen(_kontakt(isGone: true, goneAt: knapp), jetzt),
        isFalse,
      );
    });

    test('genau nach 24 Stunden faellt er weg', () {
      final genau = jetzt.subtract(GonePolicy.sichtbarkeit);
      expect(
        GonePolicy.abgelaufen(_kontakt(isGone: true, goneAt: genau), jetzt),
        isTrue,
      );
    });

    test('ein lebendes Konto laeuft nie ab, auch mit Zeitpunkt nicht', () {
      final alt = jetzt.subtract(const Duration(days: 5));
      expect(
        GonePolicy.abgelaufen(_kontakt(isGone: false, goneAt: alt), jetzt),
        isFalse,
      );
    });

    test('fort, aber ohne Zeitpunkt: nichts wird geraeumt', () {
      // Bestandsdaten. Sie wegzuwerfen, nur weil der Zeitpunkt fehlt, waere
      // der falsche Weg — sie bekommen ihn nachgetragen.
      expect(
        GonePolicy.abgelaufen(_kontakt(isGone: true), jetzt),
        isFalse,
      );
      expect(GonePolicy.brauchtNachtrag(_kontakt(isGone: true)), isTrue);
    });

    test('ein lebender Kontakt braucht keinen Nachtrag', () {
      expect(GonePolicy.brauchtNachtrag(_kontakt()), isFalse);
    });
  });

  group('abgelaufene', () {
    test('trennt faellige von noch laufenden und lebenden', () {
      final contacts = [
        _kontakt(id: 'lebt'),
        _kontakt(
            id: 'frisch',
            isGone: true,
            goneAt: jetzt.subtract(const Duration(hours: 3))),
        _kontakt(
            id: 'faellig',
            isGone: true,
            goneAt: jetzt.subtract(const Duration(hours: 25))),
        _kontakt(id: 'ohneZeit', isGone: true),
      ];
      expect(GonePolicy.abgelaufene(contacts, jetzt), ['faellig']);
    });

    test('leere Liste ergibt nichts zu tun', () {
      expect(GonePolicy.abgelaufene(const [], jetzt), isEmpty);
    });
  });

  group('Contact traegt goneAt ueber die Platte', () {
    test('Hin und zurueck erhaelt den Zeitpunkt', () {
      final geloescht = DateTime(2026, 9, 3, 2, 30);
      final zurueck = Contact.fromMap(
          _kontakt(isGone: true, goneAt: geloescht).toMap());
      expect(zurueck.isGone, isTrue);
      expect(zurueck.goneAt, geloescht);
    });

    test('ein Kontakt ohne Zeitpunkt bleibt ohne', () {
      final zurueck = Contact.fromMap(_kontakt().toMap());
      expect(zurueck.goneAt, isNull);
    });

    test('copyWith kann den Zeitpunkt setzen und wieder entfernen', () {
      final mit = _kontakt().copyWith(isGone: true, goneAt: jetzt);
      expect(mit.goneAt, jetzt);
      expect(mit.copyWith(goneAt: null).goneAt, isNull);
      // Ohne Angabe bleibt er stehen — sonst loeschte jedes copyWith die
      // Frist und der Kontakt bliebe fuer immer sichtbar.
      expect(mit.copyWith(displayName: 'Anders').goneAt, jetzt);
    });
  });
}
