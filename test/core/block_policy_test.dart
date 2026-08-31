import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/contact_model.dart';
import 'package:kryptaapp/features/messenger/logic/block_policy.dart';

/// Was das Aufheben einer Blockierung wiederherstellt.
///
/// Bisher landete jeder entblockte Kontakt auf `keyChanged` und musste erst
/// wieder bestaetigt werden. Der Gedanke dahinter ist richtig: wer wegen eines
/// Schluesselwechsels blockiert wurde, soll ueber Blockieren und Entblocken
/// nicht an der Bestaetigung vorbeikommen.
///
/// Nur traf es eben auch jeden anderen. Wer einen ganz normalen, bestaetigten
/// Kontakt kurz blockiert, will danach schreiben koennen und nicht erst wieder
/// eine Sicherheitsnummer vergleichen.
///
/// Deshalb wird gemerkt, wie es vor der Blockierung stand, und genau das
/// kommt zurueck.
void main() {
  Contact kontakt({TrustState? vorher}) => Contact(
        id: 'marco',
        displayName: 'Marco',
        publicKey: Uint8List.fromList([1, 2, 3]),
        addedAt: DateTime(2026, 8, 1),
        trustState: TrustState.blocked,
        trustBeforeBlock: vorher,
      );

  test('ein bestaetigter Kontakt ist danach wieder bestaetigt', () {
    expect(BlockPolicy.afterUnblock(kontakt(vorher: TrustState.verified)),
        TrustState.verified);
  });

  test('ein unbestaetigter bleibt unbestaetigt — und darf schreiben', () {
    expect(BlockPolicy.afterUnblock(kontakt(vorher: TrustState.unverified)),
        TrustState.unverified);
  });

  test('wer wegen Schluesselwechsel blockiert war, muss weiter bestaetigen', () {
    // Der Grund, aus dem es die Regel ueberhaupt gibt: Blockieren und
    // Entblocken darf kein Weg an der Bestaetigung vorbei sein.
    expect(BlockPolicy.afterUnblock(kontakt(vorher: TrustState.keyChanged)),
        TrustState.keyChanged);
  });

  test('ohne Erinnerung wird auf Nummer sicher gegangen', () {
    // Bestandskontakte, die vor dieser Aenderung blockiert wurden, tragen den
    // Vermerk nicht. Fuer die bleibt es beim bisherigen Verhalten.
    expect(BlockPolicy.afterUnblock(kontakt()), TrustState.keyChanged);
  });

  test('ein nicht blockierter Kontakt bleibt, wie er ist', () {
    final normal = Contact(
      id: 'marco',
      displayName: 'Marco',
      publicKey: Uint8List.fromList([1, 2, 3]),
      addedAt: DateTime(2026, 8, 1),
      trustState: TrustState.verified,
    );
    expect(BlockPolicy.afterUnblock(normal), TrustState.verified);
  });
}
