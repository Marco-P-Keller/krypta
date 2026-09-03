import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/contact_model.dart';
import 'package:kryptaapp/features/messenger/logic/session_reset_policy.dart';

/// Wann die naechste Nachricht an einen Kontakt wieder einen Handschlag
/// tragen muss.
///
/// Der Anlass: der Kollege hat den Chat in seiner Liste geloescht. Damit war
/// seine Sitzung weg — meine aber nicht, und der Handschlag-Kopf `ek` geht nur
/// mit der *ersten* Nachricht einer Sitzung mit. Alles Weitere lief ins Leere
/// und wurde bei ihm stumm verworfen. Auch ihn per QR-Code erneut
/// hinzuzufuegen half nicht: fuer einen bereits angenommenen Kontakt aendert
/// sich dabei kein Zustand, also passierte gar nichts — gemeldet wurde
/// trotzdem „verifiziert".
///
/// Wer jemanden erneut hinzufuegt, den er schon hat, meint „fang mit dem von
/// vorn an". Genau diese Geste muss die Sitzung verwerfen.
void main() {
  Contact kontakt({
    ContactRequestState zustand = ContactRequestState.established,
    TrustState vertrauen = TrustState.unverified,
  }) =>
      Contact(
        id: 'marco',
        displayName: 'Marco',
        publicKey: Uint8List.fromList([1, 2, 3]),
        addedAt: DateTime(2026, 8, 1),
        trustState: vertrauen,
        requestState: zustand,
      );

  group('Verwerfen und Neuaufbau gehoeren zusammen', () {
    // Der Fund aus dem Geraetetest von Build 100 (03.09.2026): der ID-Weg
    // warf die Sitzung weg und kehrte zurueck, ohne etwas zu senden. Die
    // Gegenseite erfuhr nichts, behielt ihre Sitzung, und weil eine laufende
    // Sitzung nie wieder einen `ek`-Kopf schickt, heilte auch nichts mehr.
    // Der Kollege sah fuer immer „Anfrage gesendet".
    for (final zustand in ContactRequestState.values) {
      test('$zustand: erneutes Hinzufuegen verlangt einen neuen Handschlag',
          () {
        expect(
          SessionResetPolicy.brauchtNeuenHandschlag(
            existing: kontakt(zustand: zustand),
            schluesselGleich: true,
          ),
          isTrue,
          reason: 'ohne Handschlag bleibt die Gegenseite stumm',
        );
      });
    }

    test('blockiert: kein Neuaufbau', () {
      // Mit jemandem, den ich ausdruecklich gesperrt habe, still eine neue
      // Sitzung aufzubauen waere das Gegenteil dessen, was die Sperre soll.
      expect(
        SessionResetPolicy.brauchtNeuenHandschlag(
          existing: kontakt(vertrauen: TrustState.blocked),
          schluesselGleich: true,
        ),
        isFalse,
      );
    });

    test('geaenderter Schluessel: kein Neuaufbau', () {
      // Der Kontakt wandert gleich in „Schluessel geaendert" und ist gesperrt,
      // bis er erneut bestaetigt wurde. Einen Handschlag mit einem Schluessel
      // aufzubauen, dem gerade misstraut wird, waere genau falsch herum.
      expect(
        SessionResetPolicy.brauchtNeuenHandschlag(
          existing: kontakt(),
          schluesselGleich: false,
        ),
        isFalse,
      );
    });

    test('blockiert UND geaenderter Schluessel: erst recht nicht', () {
      expect(
        SessionResetPolicy.brauchtNeuenHandschlag(
          existing: kontakt(vertrauen: TrustState.blocked),
          schluesselGleich: false,
        ),
        isFalse,
      );
    });

    test('die Regel ist nie strenger als onReAdd', () {
      // brauchtNeuenHandschlag darf das Verwerfen nur einschraenken, nie
      // ausweiten: sonst wuerde verworfen, ohne dass etwas nachkommt — genau
      // der Zustand, der den Fehler ausgemacht hat.
      for (final zustand in ContactRequestState.values) {
        for (final vertrauen in TrustState.values) {
          for (final gleich in [true, false]) {
            final c = kontakt(zustand: zustand, vertrauen: vertrauen);
            if (SessionResetPolicy.brauchtNeuenHandschlag(
                existing: c, schluesselGleich: gleich)) {
              expect(SessionResetPolicy.onReAdd(c), isTrue,
                  reason: '$zustand/$vertrauen/$gleich');
            }
          }
        }
      }
    });
  });

  group('Die Spur der Sitzungskennungen', () {
    // `peerSeenPsids` haelt fest, welche Sitzungskennungen die Gegenseite
    // schon benutzt hat — damit ein alter Handschlag nicht ein zweites Mal
    // durchgeht. Die Liste lebt normalerweise im Sitzungszustand und wird
    // beim Neuaufbau von dort uebernommen. Wird die Sitzung aber verworfen,
    // faellt der Zustand weg und die Spur mit ihm. Sie muss das ueberleben.

    test('was aufgehoben war und was in der Sitzung stand, kommt zusammen', () {
      expect(
        SessionResetPolicy.mergeLineage(['a', 'b'], ['c']),
        ['a', 'b', 'c'],
      );
    });

    test('nichts steht doppelt drin', () {
      expect(
        SessionResetPolicy.mergeLineage(['a', 'b'], ['b', 'c']),
        ['a', 'b', 'c'],
      );
    });

    test('leer bleibt leer', () {
      expect(SessionResetPolicy.mergeLineage([], []), isEmpty);
    });

    test('die Liste waechst nicht unbegrenzt — das Aelteste faellt', () {
      // Ohne Deckel wuechse die Spur mit jedem Neuaufbau weiter und landete
      // in dieser Groesse auf der Platte.
      final viele = [
        for (var i = 0; i < SessionResetPolicy.maxLineage + 5; i++) 's$i',
      ];

      final spur = SessionResetPolicy.mergeLineage(viele, ['neu']);

      expect(spur.length, SessionResetPolicy.maxLineage);
      expect(spur.last, 'neu', reason: 'das Neueste muss drin bleiben');
      expect(spur.contains('s0'), isFalse, reason: 'das Aelteste faellt');
    });
  });

  group('Erneut hinzufuegen', () {
    test('ein angenommener Kontakt bekommt eine frische Sitzung', () {
      // Der eigentliche Fehlerfall: hier passierte bisher nichts.
      expect(
        SessionResetPolicy.onReAdd(
            kontakt(zustand: ContactRequestState.established)),
        isTrue,
      );
    });

    test('eine offene eigene Anfrage ebenso', () {
      expect(
        SessionResetPolicy.onReAdd(
            kontakt(zustand: ContactRequestState.outgoing)),
        isTrue,
      );
    });

    test('eine offene fremde Anfrage ebenso', () {
      expect(
        SessionResetPolicy.onReAdd(
            kontakt(zustand: ContactRequestState.incoming)),
        isTrue,
      );
    });

    test('nach eigener Ablehnung ebenso', () {
      expect(
        SessionResetPolicy.onReAdd(
            kontakt(zustand: ContactRequestState.declined)),
        isTrue,
      );
    });

    test('ein blockierter Kontakt bekommt KEINE frische Sitzung', () {
      // Blockiert bleibt blockiert. Eine Sitzung mit jemandem neu aufzubauen,
      // den ich ausdruecklich gesperrt habe, waere das Gegenteil dessen, was
      // die Sperre soll — und zwar still, ohne dass ich es sehe.
      expect(
        SessionResetPolicy.onReAdd(kontakt(vertrauen: TrustState.blocked)),
        isFalse,
      );
    });
  });
}
