// Regression tests for the Build-61 delivery failure (2026-06).
//
// Root cause: the X3DH handshake was internally inconsistent — every path
// a NEW session could take produced different shared secrets on sender and
// receiver, so the first message (and the whole session) never decrypted:
//
//  1. Bundle WITH one-time prekey: sender computed 4-DH, but the receiver
//     can never mirror DH4 (no opkId is transmitted and no receiver-side
//     OTP consumption exists) → receiver always computed 3-DH.
//  2. Fallback (no bundle): sender derived everything against the
//     recipient's IDENTITY key, but the receiver unconditionally answered
//     with its signed prekey whenever one existed (= always).
//  3. The receiver could not look up a rotated signed prekey because no
//     spkId traveled with the session header.
//
// These tests pin the consistent protocol: 3-DH everywhere, fallback
// mirrored on identity keys, signed prekeys resolvable by id.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/encryption/key_pair_model.dart';
import 'package:kryptaapp/security/prekey/prekey_bundle.dart';
import 'package:kryptaapp/security/prekey/prekey_manager.dart';
import 'package:kryptaapp/security/ratchet/double_ratchet.dart';
import 'package:kryptaapp/security/ratchet/ratchet_state.dart';
import 'package:kryptaapp/security/session/session_handshake_service.dart';
import 'package:kryptaapp/services/storage/encrypted_local_store.dart';

/// In-memory store so PreKeyManager can persist without platform channels.
class _MemStore extends EncryptedLocalStore {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> saveDecoyData(String key, dynamic data) async {
    _data[key] = jsonDecode(jsonEncode(data));
  }

  @override
  Future<dynamic> loadDecoyData(String key) async => _data[key];
}

Future<KryptaKeyPair> _newX25519Pair() async {
  final kp = await X25519().newKeyPair();
  return KryptaKeyPair(
    privateKey: Uint8List.fromList(await kp.extractPrivateKeyBytes()),
    publicKey: Uint8List.fromList((await kp.extractPublicKey()).bytes),
  );
}

/// Signs [preKeyPublic] exactly like PreKeyManager.signPreKey does.
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
  late KryptaKeyPair receiverIdentity;
  late KryptaKeyPair receiverSpk;
  late KryptaKeyPair receiverOtp;
  late Uint8List spkSignature;
  late Uint8List signingPub;

  // AAD is the sender's uid on both sides (sender: utf8(userId),
  // receiver: utf8(contact.id) — same value).
  final ad = Uint8List.fromList(utf8.encode('sender-uid-0123456789'));
  final plaintext = Uint8List.fromList(utf8.encode('hallo marco — test 61'));

  setUp(() async {
    senderIdentity = await _newX25519Pair();
    receiverIdentity = await _newX25519Pair();
    receiverSpk = await _newX25519Pair();
    receiverOtp = await _newX25519Pair();
    final (sig, sigPk) =
        await _signPreKey(receiverSpk.publicKey, receiverIdentity.privateKey);
    spkSignature = sig;
    signingPub = sigPk;
  });

  PreKeyBundle bundle({bool withOtp = false}) => PreKeyBundle(
        identityPublicKey: receiverIdentity.publicKey,
        signedPreKeyPublic: receiverSpk.publicKey,
        signedPreKeySignature: spkSignature,
        signedPreKeyId: 7,
        oneTimePreKeyPublic: withOtp ? receiverOtp.publicKey : null,
        oneTimePreKeyId: withOtp ? 42 : null,
        signingPublicKey: signingPub,
      );

  group('X3DH sender/receiver consistency', () {
    test(
        'bundle WITH one-time prekey: first message decrypts on a receiver '
        'that has no way to mirror DH4 (Build-61 delivery bug)', () async {
      final out = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: senderIdentity,
        bundle: bundle(withOtp: true),
      );

      final (_, msg) = await DoubleRatchet.encrypt(
        state: out.ratchetState,
        plaintext: plaintext,
        associatedData: ad,
      );

      // The app's receive path never passes oneTimePreKeyPrivate — there is
      // no opkId on the wire to even find it. The handshake must still match.
      final inState = await SessionHandshakeService.createInboundSession(
        identityKeyPair: receiverIdentity,
        signedPreKeyPrivate: receiverSpk.privateKey,
        signedPreKeyPublic: receiverSpk.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: out.ephemeralPublicKey,
      );

      final (_, decrypted) = await DoubleRatchet.decrypt(
        state: inState,
        message: msg,
        associatedData: ad,
      );
      expect(decrypted, equals(plaintext));
    });

    test('bundle WITHOUT one-time prekey: first message decrypts (the only '
        'path that already worked — regression guard)', () async {
      final out = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: senderIdentity,
        bundle: bundle(withOtp: false),
      );

      final (_, msg) = await DoubleRatchet.encrypt(
        state: out.ratchetState,
        plaintext: plaintext,
        associatedData: ad,
      );

      final inState = await SessionHandshakeService.createInboundSession(
        identityKeyPair: receiverIdentity,
        signedPreKeyPrivate: receiverSpk.privateKey,
        signedPreKeyPublic: receiverSpk.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: out.ephemeralPublicKey,
      );

      final (_, decrypted) = await DoubleRatchet.decrypt(
        state: inState,
        message: msg,
        associatedData: ad,
      );
      expect(decrypted, equals(plaintext));
    });

    test('outbound session exposes the bundle signedPreKeyId so it can travel '
        'in the session header', () async {
      final out = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: senderIdentity,
        bundle: bundle(withOtp: true),
      );
      expect(out.signedPreKeyId, 7);
    });
  });

  group('Fallback handshake (no bundle on server)', () {
    // Sender side of the fallback path, exactly as _initRatchetAsSender does.
    Future<(RatchetState, Uint8List ek, Uint8List ek2)> fallbackSend() async {
      final (ephPub, ephPriv) = await DoubleRatchet.generateEphemeralKeyPair();
      final (sharedSecret, eph2Pub) =
          await SessionHandshakeService.deriveFallbackSecret(
        identityPrivate: senderIdentity.privateKey,
        ephemeralPrivate: ephPriv,
        recipientIdentityPublic: receiverIdentity.publicKey,
      );
      final state = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: receiverIdentity.publicKey,
      );
      return (state, ephPub, eph2Pub);
    }

    test('receiver mirrors with IDENTITY keys → first message decrypts',
        () async {
      final (sendState, ek, ek2) = await fallbackSend();
      final (_, msg) = await DoubleRatchet.encrypt(
        state: sendState,
        plaintext: plaintext,
        associatedData: ad,
      );

      final inState = await SessionHandshakeService.createInboundSession(
        identityKeyPair: receiverIdentity,
        signedPreKeyPrivate: receiverIdentity.privateKey,
        signedPreKeyPublic: receiverIdentity.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: ek,
        senderEphemeral2Public: ek2,
      );

      final (_, decrypted) = await DoubleRatchet.decrypt(
        state: inState,
        message: msg,
        associatedData: ad,
      );
      expect(decrypted, equals(plaintext));
    });

    test('receiver answering with its signed prekey CANNOT decrypt — '
        'documents why key selection must pick identity keys here', () async {
      final (sendState, ek, ek2) = await fallbackSend();
      final (_, msg) = await DoubleRatchet.encrypt(
        state: sendState,
        plaintext: plaintext,
        associatedData: ad,
      );

      final inState = await SessionHandshakeService.createInboundSession(
        identityKeyPair: receiverIdentity,
        signedPreKeyPrivate: receiverSpk.privateKey,
        signedPreKeyPublic: receiverSpk.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: ek,
        senderEphemeral2Public: ek2,
      );

      await expectLater(
        DoubleRatchet.decrypt(state: inState, message: msg, associatedData: ad),
        throwsA(anything),
      );
    });
  });

  group('resolveInboundHandshakeKeys', () {
    SignedPreKey spk(int id, KryptaKeyPair kp) => SignedPreKey(
          id: id,
          publicKey: kp.publicKey,
          privateKey: kp.privateKey,
          createdAt: DateTime.now(),
        );

    test('fallback message (ek2 present) → identity keys, even when a signed '
        'prekey exists', () async {
      final current = spk(8, receiverSpk);
      final (priv, pub) = SessionHandshakeService.resolveInboundHandshakeKeys(
        isFallback: true,
        signedPreKeyId: null,
        identityKeyPair: receiverIdentity,
        currentSignedPreKey: current,
        findSignedPreKeyById: (_) => current,
      );
      expect(pub, equals(receiverIdentity.publicKey));
      expect(priv, equals(receiverIdentity.privateKey));
    });

    test('bundle message with spkId → resolves the matching (possibly '
        'previous) signed prekey', () async {
      final previous = spk(7, receiverSpk);
      final current = spk(8, await _newX25519Pair());
      final (priv, pub) = SessionHandshakeService.resolveInboundHandshakeKeys(
        isFallback: false,
        signedPreKeyId: 7,
        identityKeyPair: receiverIdentity,
        currentSignedPreKey: current,
        findSignedPreKeyById: (id) => id == 7 ? previous : null,
      );
      expect(pub, equals(previous.publicKey));
      expect(priv, equals(previous.privateKey));
    });

    test('bundle message with unknown spkId → falls back to current signed '
        'prekey', () async {
      final current = spk(8, receiverSpk);
      final (priv, pub) = SessionHandshakeService.resolveInboundHandshakeKeys(
        isFallback: false,
        signedPreKeyId: 99,
        identityKeyPair: receiverIdentity,
        currentSignedPreKey: current,
        findSignedPreKeyById: (_) => null,
      );
      expect(pub, equals(current.publicKey));
      expect(priv, equals(current.privateKey));
    });

    test('bundle message without spkId → current signed prekey', () async {
      final current = spk(8, receiverSpk);
      final (priv, pub) = SessionHandshakeService.resolveInboundHandshakeKeys(
        isFallback: false,
        signedPreKeyId: null,
        identityKeyPair: receiverIdentity,
        currentSignedPreKey: current,
        findSignedPreKeyById: (_) => null,
      );
      expect(pub, equals(current.publicKey));
      expect(priv, equals(current.privateKey));
    });

    test('no local prekeys at all → identity keys', () async {
      final (priv, pub) = SessionHandshakeService.resolveInboundHandshakeKeys(
        isFallback: false,
        signedPreKeyId: null,
        identityKeyPair: receiverIdentity,
        currentSignedPreKey: null,
        findSignedPreKeyById: (_) => null,
      );
      expect(pub, equals(receiverIdentity.publicKey));
      expect(priv, equals(receiverIdentity.privateKey));
    });
  });

  group('PreKeyBundle publishing', () {
    test('buildBundle publishes NO one-time prekey until receiver-side OTP '
        'consumption exists end-to-end', () async {
      final mgr = PreKeyManager(localStore: _MemStore());
      await mgr.init();
      await mgr.generateSignedPreKey(receiverIdentity);
      await mgr.generateOneTimePreKeys(5);

      final (sig, sigPk) = await _signPreKey(
          mgr.currentSignedPreKey!.publicKey, receiverIdentity.privateKey);
      final b = mgr.buildBundle(receiverIdentity, sig, signingPublicKey: sigPk);

      expect(b.oneTimePreKeyPublic, isNull);
      expect(b.oneTimePreKeyId, isNull);
      expect(b.toMap().containsKey('opk'), isFalse);
      expect(b.toMap().containsKey('opkId'), isFalse);
    });
  });

  group('Session heal (re-handshake over stale state)', () {
    test('a fresh inbound session derived from the message header decrypts '
        'what the stale session cannot', () async {
      // The receiver still holds an OLD session…
      final staleOut = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: senderIdentity,
        bundle: bundle(),
      );
      final staleReceiverState =
          await SessionHandshakeService.createInboundSession(
        identityKeyPair: receiverIdentity,
        signedPreKeyPrivate: receiverSpk.privateKey,
        signedPreKeyPublic: receiverSpk.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: staleOut.ephemeralPublicKey,
      );

      // …while the sender lost its state and re-handshakes.
      final freshOut = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: senderIdentity,
        bundle: bundle(),
      );
      final (_, msg) = await DoubleRatchet.encrypt(
        state: freshOut.ratchetState,
        plaintext: plaintext,
        associatedData: ad,
      );

      // Old state must fail…
      await expectLater(
        DoubleRatchet.decrypt(
            state: staleReceiverState, message: msg, associatedData: ad),
        throwsA(anything),
      );

      // …and a session re-derived from the new header must succeed.
      final healedState = await SessionHandshakeService.createInboundSession(
        identityKeyPair: receiverIdentity,
        signedPreKeyPrivate: receiverSpk.privateKey,
        signedPreKeyPublic: receiverSpk.publicKey,
        senderIdentityPublic: senderIdentity.publicKey,
        senderEphemeralPublic: freshOut.ephemeralPublicKey,
      );
      final (_, decrypted) = await DoubleRatchet.decrypt(
        state: healedState,
        message: msg,
        associatedData: ad,
      );
      expect(decrypted, equals(plaintext));
    });
  });
}
