// KRY-01 (Security-Audit 2026-09-03): das Vorabschluesselbuendel darf die
// Identitaet eines Kontakts nicht bestimmen.
//
// Vorher holte `_initRatchetAsSender` das Buendel aus `prekeys/{id}` und gab
// es unbesehen an den Handschlag weiter. DH2 lief gegen
// `bundle.identityPublicKey`, und die Signatur des Vorabschluessels wurde mit
// `bundle.signingPublicKey` geprueft — beide Werte aus demselben
// Serverdokument. Ein Server, der dieses Dokument schreiben kann, konnte ein
// in sich stimmiges Buendel mit eigenen Schluesseln ausliefern und jede
// Nachricht einer neu aufgebauten Sitzung mitlesen. Die Sicherheitsnummer,
// die aus `publicKeys/` stammt, blieb dabei gruen.
//
// Der Anker ist jetzt der lokal gespeicherte Kontaktschluessel. Diese Tests
// halten die Invariante fest und pruefen ausserdem, was ein Server mit dem
// Rest des Buendels noch anrichten kann — naemlich Zustellung verhindern,
// aber nicht mitlesen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/encryption/key_pair_model.dart';
import 'package:kryptaapp/security/prekey/prekey_bundle.dart';
import 'package:kryptaapp/security/ratchet/double_ratchet.dart';
import 'package:kryptaapp/security/session/session_handshake_service.dart';

Future<KryptaKeyPair> _newX25519Pair() async {
  final kp = await X25519().newKeyPair();
  return KryptaKeyPair(
    privateKey: Uint8List.fromList(await kp.extractPrivateKeyBytes()),
    publicKey: Uint8List.fromList((await kp.extractPublicKey()).bytes),
  );
}

/// Signiert [preKeyPublic] genau so wie `PreKeyManager.signPreKey`.
Future<(Uint8List, Uint8List)> _signPreKey(
    Uint8List preKeyPublic, Uint8List identityPrivate) async {
  final ed = Ed25519();
  final signingKp = await ed.newKeyPairFromSeed(identityPrivate);
  final signingPub =
      Uint8List.fromList((await signingKp.extractPublicKey()).bytes);
  final sig = await ed.sign(preKeyPublic, keyPair: signingKp);
  return (Uint8List.fromList(sig.bytes), signingPub);
}

void main() {
  late KryptaKeyPair senderIdentity;
  late KryptaKeyPair contactIdentity;
  late KryptaKeyPair contactSpk;

  /// Der Angreifer: kontrolliert `prekeys/{kontakt}`, hat aber weder den
  /// privaten Identitaetsschluessel des Kontakts noch Zugriff auf den
  /// lokalen Speicher des Absenders.
  late KryptaKeyPair angreiferIdentity;
  late KryptaKeyPair angreiferSpk;

  final ad = Uint8List.fromList(utf8.encode('sender-uid-0123456789'));
  final plaintext = Uint8List.fromList(utf8.encode('nur fuer den kontakt'));

  setUp(() async {
    senderIdentity = await _newX25519Pair();
    contactIdentity = await _newX25519Pair();
    contactSpk = await _newX25519Pair();
    angreiferIdentity = await _newX25519Pair();
    angreiferSpk = await _newX25519Pair();
  });

  /// Ein Buendel, wie der Kontakt es selbst veroeffentlicht.
  Future<PreKeyBundle> echtesBuendel() async {
    final (sig, sigPk) =
        await _signPreKey(contactSpk.publicKey, contactIdentity.privateKey);
    return PreKeyBundle(
      identityPublicKey: contactIdentity.publicKey,
      signedPreKeyPublic: contactSpk.publicKey,
      signedPreKeySignature: sig,
      signedPreKeyId: 7,
      signingPublicKey: sigPk,
    );
  }

  group('KRY-01: das Buendel bestimmt die Identitaet nicht', () {
    test('T1 — echtes Buendel: Sitzung entsteht und der Kontakt liest mit',
        () async {
      final out = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: senderIdentity,
        bundle: await echtesBuendel(),
        pinnedIdentityPublicKey: contactIdentity.publicKey,
      );

      final (_, msg) = await DoubleRatchet.encrypt(
        state: out.ratchetState,
        plaintext: plaintext,
        associatedData: ad,
      );

      final inState = await SessionHandshakeService.createInboundSession(
        identityKeyPair: contactIdentity,
        signedPreKeyPrivate: contactSpk.privateKey,
        signedPreKeyPublic: contactSpk.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: out.ephemeralPublicKey,
      );

      final (_, entschluesselt) = await DoubleRatchet.decrypt(
        state: inState,
        message: msg,
        associatedData: ad,
      );
      expect(entschluesselt, equals(plaintext));
    });

    test('T2 — fremder Identitaetsschluessel im Buendel wird abgewiesen',
        () async {
      final buendel = await echtesBuendel();
      final vertauscht = PreKeyBundle(
        identityPublicKey: angreiferIdentity.publicKey, // <— vertauscht
        signedPreKeyPublic: buendel.signedPreKeyPublic,
        signedPreKeySignature: buendel.signedPreKeySignature,
        signedPreKeyId: buendel.signedPreKeyId,
        signingPublicKey: buendel.signingPublicKey,
      );

      await expectLater(
        SessionHandshakeService.createOutboundSession(
          identityKeyPair: senderIdentity,
          bundle: vertauscht,
          pinnedIdentityPublicKey: contactIdentity.publicKey,
        ),
        throwsA(isA<IdentityMismatchException>()),
      );
    });

    test(
        'T3 — vollstaendig selbstkonsistentes Angreiferbuendel wird abgewiesen',
        () async {
      // Der eigentliche KRY-01-Angriff: eigener Identitaetsschluessel,
      // eigener Signaturschluessel, eigener Vorabschluessel, gueltige
      // Signatur darueber. In sich kryptographisch einwandfrei — und
      // trotzdem nicht der Kontakt.
      final (sig, sigPk) = await _signPreKey(
          angreiferSpk.publicKey, angreiferIdentity.privateKey);
      final angreiferbuendel = PreKeyBundle(
        identityPublicKey: angreiferIdentity.publicKey,
        signedPreKeyPublic: angreiferSpk.publicKey,
        signedPreKeySignature: sig,
        signedPreKeyId: 99,
        signingPublicKey: sigPk,
      );

      // Gegenprobe: die Signatur des Buendels ist tatsaechlich gueltig —
      // der Test faellt also nicht versehentlich ueber eine kaputte
      // Signatur, sondern ueber die Identitaetsbindung.
      expect(
        await SessionHandshakeService.verifySignedPreKey(
          preKeyPublic: angreiferbuendel.signedPreKeyPublic,
          signature: angreiferbuendel.signedPreKeySignature,
          identityPublicKey: angreiferbuendel.identityPublicKey,
          signingPublicKey: angreiferbuendel.signingPublicKey,
        ),
        isTrue,
      );

      await expectLater(
        SessionHandshakeService.createOutboundSession(
          identityKeyPair: senderIdentity,
          bundle: angreiferbuendel,
          pinnedIdentityPublicKey: contactIdentity.publicKey,
        ),
        throwsA(isA<IdentityMismatchException>()),
      );
    });

    test('T4 — manipulierter Vorabschluessel: Signaturpruefung schlaegt fehl',
        () async {
      final buendel = await echtesBuendel();
      final manipuliert = PreKeyBundle(
        identityPublicKey: buendel.identityPublicKey, // Anker stimmt
        signedPreKeyPublic: angreiferSpk.publicKey, // Inhalt nicht
        signedPreKeySignature: buendel.signedPreKeySignature,
        signedPreKeyId: buendel.signedPreKeyId,
        signingPublicKey: buendel.signingPublicKey,
      );

      await expectLater(
        SessionHandshakeService.createOutboundSession(
          identityKeyPair: senderIdentity,
          bundle: manipuliert,
          pinnedIdentityPublicKey: contactIdentity.publicKey,
        ),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('T5 — ein bestaetigter Kontakt verschleiert den Angriff nicht',
        () async {
      // Der Anker ist der gespeicherte Schluessel, nicht der Vertrauensgrad.
      // Ob der Kontakt ueber die Sicherheitsnummer bestaetigt wurde, aendert
      // an der Pruefung nichts — sie greift in jedem Zustand gleich.
      final (sig, sigPk) = await _signPreKey(
          angreiferSpk.publicKey, angreiferIdentity.privateKey);

      await expectLater(
        SessionHandshakeService.createOutboundSession(
          identityKeyPair: senderIdentity,
          bundle: PreKeyBundle(
            identityPublicKey: angreiferIdentity.publicKey,
            signedPreKeyPublic: angreiferSpk.publicKey,
            signedPreKeySignature: sig,
            signedPreKeyId: 1,
            signingPublicKey: sigPk,
          ),
          pinnedIdentityPublicKey: contactIdentity.publicKey,
        ),
        throwsA(isA<IdentityMismatchException>()),
      );
    });

    test('T7 — nach einem echten Schluesselwechsel gilt der neue Schluessel',
        () async {
      // Der Kontakt wechselt seine Identitaet. Solange der Absender den
      // Wechsel nicht uebernommen hat, wird das neue Buendel abgewiesen;
      // danach traegt es.
      final neueIdentity = await _newX25519Pair();
      final neuerSpk = await _newX25519Pair();
      final (sig, sigPk) =
          await _signPreKey(neuerSpk.publicKey, neueIdentity.privateKey);
      final neuesBuendel = PreKeyBundle(
        identityPublicKey: neueIdentity.publicKey,
        signedPreKeyPublic: neuerSpk.publicKey,
        signedPreKeySignature: sig,
        signedPreKeyId: 12,
        signingPublicKey: sigPk,
      );

      await expectLater(
        SessionHandshakeService.createOutboundSession(
          identityKeyPair: senderIdentity,
          bundle: neuesBuendel,
          pinnedIdentityPublicKey: contactIdentity.publicKey, // noch alt
        ),
        throwsA(isA<IdentityMismatchException>()),
      );

      // Nach der Uebernahme des Wechsels (Weg ueber `publicKeys/` und
      // VerificationPolicy.nachSchluesselwechsel, dort getestet) ist der
      // Anker der neue Schluessel.
      final out = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: senderIdentity,
        bundle: neuesBuendel,
        pinnedIdentityPublicKey: neueIdentity.publicKey,
      );
      expect(out.signedPreKeyId, 12);
    });

    test('IdentityMismatchException laeuft in die bestehenden Fail-Closed-'
        'Faenger', () async {
      // Der Sendepfad faengt `on HandshakeException` und bricht dort ab,
      // ohne zu senden. Der neue Typ muss darunter fallen, sonst landet er
      // im allgemeinen catch und die Sitzung bliebe stehen.
      const e = IdentityMismatchException('x');
      expect(e, isA<HandshakeException>());
      expect(e.message, 'x');
    });
  });

  group('KRY-01: was ein Server mit dem Rest des Buendels noch kann', () {
    test(
        'T10 — echter Identitaetsschluessel, aber untergeschobener '
        'Vorabschluessel: niemand liest mit, auch der Angreifer nicht',
        () async {
      // Der Angreifer laesst den Identitaetsschluessel unangetastet (sonst
      // greift die Pruefung) und tauscht nur Vorabschluessel und
      // Signaturschluessel gegen eigene, korrekt signierte aus. Das Buendel
      // passiert die Identitaetsbindung.
      //
      // Entscheidend ist, was er danach hat: nichts. DH2 laeuft gegen den
      // echten Identitaetsschluessel des Kontakts, und dessen privaten Teil
      // hat er nicht. Das Ergebnis ist eine Sitzung, die niemand lesen kann
      // — Zustellungsverlust, nicht Preisgabe. Nachrichten zu verwerfen kann
      // ein Server ohnehin.
      final (sig, sigPk) = await _signPreKey(
          angreiferSpk.publicKey, angreiferIdentity.privateKey);
      final untergeschoben = PreKeyBundle(
        identityPublicKey: contactIdentity.publicKey, // echt
        signedPreKeyPublic: angreiferSpk.publicKey, // untergeschoben
        signedPreKeySignature: sig,
        signedPreKeyId: 5,
        signingPublicKey: sigPk,
      );

      final out = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: senderIdentity,
        bundle: untergeschoben,
        pinnedIdentityPublicKey: contactIdentity.publicKey,
      );
      final (_, msg) = await DoubleRatchet.encrypt(
        state: out.ratchetState,
        plaintext: plaintext,
        associatedData: ad,
      );

      // Der Angreifer spiegelt den Handschlag mit allem, was er hat: seinem
      // eigenen Identitaetsschluessel und dem privaten Teil des von ihm
      // untergeschobenen Vorabschluessels.
      final angreiferState =
          await SessionHandshakeService.createInboundSession(
        identityKeyPair: angreiferIdentity,
        signedPreKeyPrivate: angreiferSpk.privateKey,
        signedPreKeyPublic: angreiferSpk.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: out.ephemeralPublicKey,
      );
      await expectLater(
        DoubleRatchet.decrypt(
          state: angreiferState,
          message: msg,
          associatedData: ad,
        ),
        throwsA(anything),
      );

      // Und der echte Kontakt kann es ebenfalls nicht — er haelt den
      // Vorabschluessel, den er selbst veroeffentlicht hat.
      final kontaktState = await SessionHandshakeService.createInboundSession(
        identityKeyPair: contactIdentity,
        signedPreKeyPrivate: contactSpk.privateKey,
        signedPreKeyPublic: contactSpk.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: out.ephemeralPublicKey,
      );
      await expectLater(
        DoubleRatchet.decrypt(
          state: kontaktState,
          message: msg,
          associatedData: ad,
        ),
        throwsA(anything),
      );
    });

    test(
        'T8 — der Rueckfallweg ohne Buendel bleibt am Kontaktschluessel '
        'verankert', () async {
      // Haelt der Server das Buendel zurueck, leitet der Absender aus
      // `contact.publicKey` ab. Ein fremder Identitaetsschluessel kommt in
      // diesem Weg gar nicht vor, es gibt also keine Umgehung ueber das
      // Zurueckhalten des Buendels.
      final (ephPub, ephPriv) = await DoubleRatchet.generateEphemeralKeyPair();
      final (secret, eph2Pub) =
          await SessionHandshakeService.deriveFallbackSecret(
        identityPrivate: senderIdentity.privateKey,
        ephemeralPrivate: ephPriv,
        recipientIdentityPublic: contactIdentity.publicKey,
      );
      final state = await DoubleRatchet.initAsSender(
        sharedSecret: secret,
        recipientRatchetPublicKey: contactIdentity.publicKey,
      );
      final (_, msg) = await DoubleRatchet.encrypt(
        state: state,
        plaintext: plaintext,
        associatedData: ad,
      );

      // Der Kontakt spiegelt mit seinem Identitaetsschluesselpaar.
      final kontaktState = await SessionHandshakeService.createInboundSession(
        identityKeyPair: contactIdentity,
        signedPreKeyPrivate: contactIdentity.privateKey,
        signedPreKeyPublic: contactIdentity.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: ephPub,
        senderEphemeral2Public: eph2Pub,
      );
      final (_, entschluesselt) = await DoubleRatchet.decrypt(
        state: kontaktState,
        message: msg,
        associatedData: ad,
      );
      expect(entschluesselt, equals(plaintext));

      // Der Angreifer kann denselben Spiegel nicht bauen.
      final angreiferState =
          await SessionHandshakeService.createInboundSession(
        identityKeyPair: angreiferIdentity,
        signedPreKeyPrivate: angreiferIdentity.privateKey,
        signedPreKeyPublic: angreiferIdentity.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: ephPub,
        senderEphemeral2Public: eph2Pub,
      );
      await expectLater(
        DoubleRatchet.decrypt(
          state: angreiferState,
          message: msg,
          associatedData: ad,
        ),
        throwsA(anything),
      );
    });
  });
}
