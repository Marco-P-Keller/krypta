import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/contact_model.dart';
import 'package:kryptaapp/features/messenger/logic/contact_request_policy.dart';

/// Kontaktanfragen — Zustandslogik.
///
/// Bis hierher galt: eine Nachricht von jemandem, den man nicht hinzugefügt
/// hat, wurde verworfen **und vom Server gelöscht**. Fügte der Empfänger den
/// Absender später hinzu, kam sie nicht nach — sie war endgültig weg.
///
/// Neu wird die Kontaktanfrage vorgeschaltet: geschrieben wird erst nach der
/// Annahme, damit kann gar keine Nachricht verloren gehen. Entwurf in
/// `docs/KONTAKTANFRAGEN.md`.
///
/// Diese Tests decken die reine Zustandslogik ab, ohne Firebase.
void main() {
  Contact make({
    String id = 'user_aaaaaaaaaaaaaaaaaaaa',
    TrustState trust = TrustState.unverified,
    ContactRequestState request = ContactRequestState.established,
    int declineCount = 0,
  }) {
    return Contact(
      id: id,
      displayName: 'Test',
      publicKey: Uint8List.fromList(List.filled(32, 7)),
      addedAt: DateTime(2026, 8, 24),
      trustState: trust,
      requestState: request,
      declineCount: declineCount,
    );
  }

  group('Standard und Migration', () {
    test('ein neuer Kontakt gilt als angenommen', () {
      // Wer selbst hinzufügt, hat zugestimmt — der Standard darf nicht
      // „offene Anfrage" sein.
      expect(make().requestState, ContactRequestState.established);
      expect(make().declineCount, 0);
    });

    test('ein gespeicherter Kontakt ohne das neue Feld gilt als angenommen',
        () {
      // Das ist der Migrationspfad und die teuerste Stelle: ohne ihn stünden
      // alle laufenden Chats nach dem Update als offene Anfrage da, und
      // niemand könnte mehr schreiben.
      final alt = make().toMap()..remove('requestState');
      expect(Contact.fromMap(alt).requestState,
          ContactRequestState.established);
    });

    test('Zustand und Zähler überstehen Speichern und Laden', () {
      final c = make(
        request: ContactRequestState.declined,
        declineCount: 2,
      );
      final wieder = Contact.fromMap(c.toMap());
      expect(wieder.requestState, ContactRequestState.declined);
      expect(wieder.declineCount, 2);
    });
  });

  group('Senden gesperrt bis zur Annahme', () {
    test('nur ein angenommener Kontakt darf beschrieben werden', () {
      expect(make(request: ContactRequestState.established).canSendMessages,
          isTrue);
      for (final s in [
        ContactRequestState.outgoing,
        ContactRequestState.incoming,
        ContactRequestState.declined,
      ]) {
        expect(make(request: s).canSendMessages, isFalse, reason: '$s');
      }
    });

    test('blockiert und Schlüsselwechsel sperren weiterhin', () {
      // Die bestehenden Sperren dürfen durch das neue Feld nicht aufweichen.
      expect(make(trust: TrustState.blocked).canSendMessages, isFalse);
      expect(make(trust: TrustState.keyChanged).canSendMessages, isFalse);
    });
  });

  group('eingehende Anfrage annehmen oder verwerfen', () {
    test('von einem völlig Unbekannten wird angenommen', () {
      expect(
        ContactRequestPolicy.rejectIncoming(
            existing: null, openIncomingCount: 0),
        isNull,
      );
    });

    test('von einem Blockierten nicht', () {
      expect(
        ContactRequestPolicy.rejectIncoming(
          existing: make(trust: TrustState.blocked),
          openIncomingCount: 0,
        ),
        RequestRejection.blocked,
      );
    });

    test('ab der vierten Anfrage nach drei Ablehnungen nicht mehr', () {
      Contact abgelehnt(int n) => make(
            request: ContactRequestState.declined,
            declineCount: n,
          );
      expect(
          ContactRequestPolicy.rejectIncoming(
              existing: abgelehnt(2), openIncomingCount: 0),
          isNull);
      expect(
        ContactRequestPolicy.rejectIncoming(
            existing: abgelehnt(3), openIncomingCount: 0),
        RequestRejection.tooManyDeclines,
      );
    });

    test('nicht über der Obergrenze offener Anfragen', () {
      expect(
          ContactRequestPolicy.rejectIncoming(
              existing: null,
              openIncomingCount: ContactRequestPolicy.maxOpenRequests - 1),
          isNull);
      expect(
        ContactRequestPolicy.rejectIncoming(
            existing: null,
            openIncomingCount: ContactRequestPolicy.maxOpenRequests),
        RequestRejection.tooManyOpen,
      );
    });

    test('ein bereits angenommener Kontakt zählt nicht gegen die Grenze', () {
      // Sonst könnte ein voller Anfragenkorb den laufenden Betrieb mit
      // bestehenden Kontakten lahmlegen.
      expect(
        ContactRequestPolicy.rejectIncoming(
          existing: make(request: ContactRequestState.established),
          openIncomingCount: ContactRequestPolicy.maxOpenRequests,
        ),
        isNull,
      );
    });
  });

  group('Zustand nach einer eingehenden Anfrage', () {
    test('von einem Unbekannten wird eine offene Anfrage', () {
      expect(ContactRequestPolicy.stateAfterIncoming(null),
          ContactRequestState.incoming);
    });

    test('wer selbst angefragt hat, ist damit einig', () {
      // Beidseitiges Hinzufügen: beide haben zugestimmt, also kein Knopf.
      expect(
        ContactRequestPolicy.stateAfterIncoming(
            make(request: ContactRequestState.outgoing)),
        ContactRequestState.established,
      );
    });

    test('nach einer Ablehnung darf erneut angefragt werden', () {
      expect(
        ContactRequestPolicy.stateAfterIncoming(
            make(request: ContactRequestState.declined, declineCount: 1)),
        ContactRequestState.incoming,
      );
    });

    test('ein bestehender Kontakt bleibt angenommen', () {
      expect(
        ContactRequestPolicy.stateAfterIncoming(
            make(request: ContactRequestState.established)),
        ContactRequestState.established,
      );
    });
  });

  group('selbst hinzufügen', () {
    test('bei offener Anfrage der Gegenseite direkt angenommen', () {
      // Wer hinzufügt, hat zugestimmt — ihn danach noch auf „Annehmen" zu
      // schicken, wäre eine Rückfrage nach einer getroffenen Entscheidung.
      final c = ContactRequestPolicy.afterLocalAdd(
          make(request: ContactRequestState.incoming));
      expect(c.requestState, ContactRequestState.established);
    });

    test('nach eigener Ablehnung wieder eine eigene Anfrage', () {
      final c = ContactRequestPolicy.afterLocalAdd(
          make(request: ContactRequestState.declined, declineCount: 2));
      expect(c.requestState, ContactRequestState.outgoing);
      expect(c.declineCount, 0,
          reason: 'der Zähler bremst fremdes Anklopfen, nicht die eigene '
              'Meinungsänderung');
    });

    test('ein angenommener Kontakt bleibt unverändert', () {
      final c = ContactRequestPolicy.afterLocalAdd(
          make(request: ContactRequestState.established));
      expect(c.requestState, ContactRequestState.established);
    });

    test('eine bereits gesendete Anfrage bleibt gesendet', () {
      final c = ContactRequestPolicy.afterLocalAdd(
          make(request: ContactRequestState.outgoing));
      expect(c.requestState, ContactRequestState.outgoing);
    });
  });

  group('annehmen und ablehnen', () {
    test('annehmen macht den Kontakt beschreibbar', () {
      final c = ContactRequestPolicy.afterAccept(
          make(request: ContactRequestState.incoming));
      expect(c.requestState, ContactRequestState.established);
      expect(c.canSendMessages, isTrue);
    });

    test('ablehnen zählt mit', () {
      final c = ContactRequestPolicy.afterDecline(
          make(request: ContactRequestState.incoming, declineCount: 1));
      expect(c.requestState, ContactRequestState.declined);
      expect(c.declineCount, 2);
      expect(c.canSendMessages, isFalse);
    });

    test('annehmen ändert die kryptografische Vertrauenslage nicht', () {
      // Eine Anfrage anzunehmen heißt „ich kenne die Person", nicht „ich habe
      // ihren Schlüssel geprüft". Verifikation bleibt ein eigener Schritt.
      final c = ContactRequestPolicy.afterAccept(
          make(request: ContactRequestState.incoming));
      expect(c.trustState, TrustState.unverified);
    });
  });
}
