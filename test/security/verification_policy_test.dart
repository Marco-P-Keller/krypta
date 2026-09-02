import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/contact_model.dart';
import 'package:kryptaapp/features/messenger/logic/verification_policy.dart';

/// Zwei Invarianten rund um das Bestaetigen eines Kontakts.
///
/// Der Anlass: Daniel wollte das Verifizieren verbessern und hat Code und
/// Bildschirmfotos extern begutachten lassen. Zwei der Funde halten der
/// Gegenprobe am Quelltext stand.
///
/// **Erstens** wurde `verifiedFingerprint` an fuenf Stellen geschrieben und
/// nirgends gelesen. Der gespeicherte Beweis, WELCHER Schluessel bestaetigt
/// wurde, lag ungenutzt herum — „bestaetigt" hing allein an einem Enum-Wert.
///
/// **Zweitens** ueberschrieb die Schluesselwechsel-Erkennung `trustState`
/// bedingungslos mit `keyChanged`, auch bei einem blockierten Kontakt. Damit
/// hob ein Schluesselwechsel die Blockierung auf.
void main() {
  final schluessel = Uint8List.fromList(List.generate(32, (i) => i));
  final andererSchluessel = Uint8List.fromList(List.generate(32, (i) => 255 - i));

  Contact kontakt({
    required TrustState zustand,
    String? bestaetigterFingerprint,
    TrustState? vorDerSperre,
    Uint8List? key,
  }) =>
      Contact(
        id: 'marco1',
        displayName: 'Marco',
        publicKey: key ?? schluessel,
        addedAt: DateTime(2026, 9, 1),
        trustState: zustand,
        trustBeforeBlock: vorDerSperre,
        verifiedFingerprint: bestaetigterFingerprint,
      );

  group('bestaetigt gilt nur fuer den bestaetigten Schluessel', () {
    test('passender Fingerprint: bestaetigt', () {
      final c = kontakt(
        zustand: TrustState.verified,
        bestaetigterFingerprint: Contact.computeFullFingerprint(schluessel),
      );
      expect(VerificationPolicy.giltAlsBestaetigt(c), isTrue);
    });

    test('fremder Fingerprint: NICHT bestaetigt', () {
      // Der gefaehrliche Fall: der Zustand sagt „verified", der Beweis
      // gehoert aber zu einem anderen Schluessel.
      final c = kontakt(
        zustand: TrustState.verified,
        bestaetigterFingerprint:
            Contact.computeFullFingerprint(andererSchluessel),
      );
      expect(VerificationPolicy.giltAlsBestaetigt(c), isFalse);
    });

    test('gar kein Fingerprint: NICHT bestaetigt', () {
      // Bestandsdatensaetze und beschaedigte Zustaende fallen auf
      // unbestaetigt zurueck, nie auf bestaetigt.
      final c = kontakt(zustand: TrustState.verified);
      expect(VerificationPolicy.giltAlsBestaetigt(c), isFalse);
    });

    test('unbestaetigter Kontakt bleibt unbestaetigt', () {
      final c = kontakt(
        zustand: TrustState.unverified,
        bestaetigterFingerprint: Contact.computeFullFingerprint(schluessel),
      );
      expect(VerificationPolicy.giltAlsBestaetigt(c), isFalse);
    });
  });

  group('ein Schluesselwechsel hebt keine Blockierung auf', () {
    test('blockiert bleibt blockiert, der Wechsel wandert in die Erinnerung',
        () {
      final c = kontakt(
        zustand: TrustState.blocked,
        vorDerSperre: TrustState.verified,
      );
      final n = VerificationPolicy.nachSchluesselwechsel(c);
      expect(n.trustState, TrustState.blocked,
          reason: 'sonst haette ein Schluesselwechsel entblockt');
      expect(n.trustBeforeBlock, TrustState.keyChanged,
          reason: 'nach dem Entblocken muss die Warnung dastehen');
    });

    test('nicht blockiert: der Zustand wird keyChanged', () {
      final c = kontakt(zustand: TrustState.verified);
      final n = VerificationPolicy.nachSchluesselwechsel(c);
      expect(n.trustState, TrustState.keyChanged);
      expect(n.trustBeforeBlock, isNull);
    });

    test('blockiert und vorher schon keyChanged bleibt keyChanged', () {
      final c = kontakt(
        zustand: TrustState.blocked,
        vorDerSperre: TrustState.keyChanged,
      );
      final n = VerificationPolicy.nachSchluesselwechsel(c);
      expect(n.trustState, TrustState.blocked);
      expect(n.trustBeforeBlock, TrustState.keyChanged);
    });
  });
}
