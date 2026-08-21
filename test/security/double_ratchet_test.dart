import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/ratchet/double_ratchet.dart';
import 'package:kryptaapp/security/ratchet/ratchet_message.dart';
import 'package:kryptaapp/security/ratchet/ratchet_state.dart';

void main() {
  group('DoubleRatchet', () {
    late Uint8List sharedSecret;
    late Uint8List bobPub;
    late Uint8List bobPriv;

    setUp(() async {
      // Simulate shared secret from X3DH
      sharedSecret = Uint8List.fromList(List.generate(32, (i) => i));

      // Bob's initial ratchet key pair
      final kp = await X25519().newKeyPair();
      bobPub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
      bobPriv = Uint8List.fromList(await kp.extractPrivateKeyBytes());
    });

    test('Alice sends, Bob receives — basic flow', () async {
      final alice = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: bobPub,
      );
      final bob = DoubleRatchet.initAsReceiver(
        sharedSecret: sharedSecret,
        ratchetPublicKey: bobPub,
        ratchetPrivateKey: bobPriv,
      );

      final ad = Uint8List.fromList(utf8.encode('test'));
      final plaintext = Uint8List.fromList(utf8.encode('Hello Bob!'));

      final (alice2, msg) = await DoubleRatchet.encrypt(
        state: alice,
        plaintext: plaintext,
        associatedData: ad,
      );

      final (bob2, decrypted) = await DoubleRatchet.decrypt(
        state: bob,
        message: msg,
        associatedData: ad,
      );

      expect(utf8.decode(decrypted), 'Hello Bob!');
      expect(alice2.sendMessageNumber, 1);
      expect(bob2.receiveMessageNumber, 1);
    });

    test('multiple messages in sequence', () async {
      var alice = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: bobPub,
      );
      var bob = DoubleRatchet.initAsReceiver(
        sharedSecret: sharedSecret,
        ratchetPublicKey: bobPub,
        ratchetPrivateKey: bobPriv,
      );

      final ad = Uint8List.fromList(utf8.encode('chat'));

      for (var i = 0; i < 10; i++) {
        final pt = Uint8List.fromList(utf8.encode('Message $i'));
        final (a2, msg) = await DoubleRatchet.encrypt(
          state: alice,
          plaintext: pt,
          associatedData: ad,
        );
        alice = a2;

        final (b2, dec) = await DoubleRatchet.decrypt(
          state: bob,
          message: msg,
          associatedData: ad,
        );
        bob = b2;

        expect(utf8.decode(dec), 'Message $i');
      }
    });

    test('bidirectional messages (ping-pong)', () async {
      var alice = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: bobPub,
      );
      var bob = DoubleRatchet.initAsReceiver(
        sharedSecret: sharedSecret,
        ratchetPublicKey: bobPub,
        ratchetPrivateKey: bobPriv,
      );

      final ad = Uint8List.fromList(utf8.encode('chat'));

      // Alice → Bob
      final (a2, msg1) = await DoubleRatchet.encrypt(
        state: alice,
        plaintext: Uint8List.fromList(utf8.encode('Hi Bob')),
        associatedData: ad,
      );
      alice = a2;
      final (b2, dec1) = await DoubleRatchet.decrypt(
        state: bob, message: msg1, associatedData: ad);
      bob = b2;
      expect(utf8.decode(dec1), 'Hi Bob');

      // Bob → Alice
      final (b3, msg2) = await DoubleRatchet.encrypt(
        state: bob,
        plaintext: Uint8List.fromList(utf8.encode('Hi Alice')),
        associatedData: ad,
      );
      bob = b3;
      final (a3, dec2) = await DoubleRatchet.decrypt(
        state: alice, message: msg2, associatedData: ad);
      alice = a3;
      expect(utf8.decode(dec2), 'Hi Alice');

      // Alice → Bob again
      final (a4, msg3) = await DoubleRatchet.encrypt(
        state: alice,
        plaintext: Uint8List.fromList(utf8.encode('Ping')),
        associatedData: ad,
      );
      alice = a4;
      final (b4, dec3) = await DoubleRatchet.decrypt(
        state: bob, message: msg3, associatedData: ad);
      bob = b4;
      expect(utf8.decode(dec3), 'Ping');
    });

    test('wrong key fails decryption', () async {
      final alice = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: bobPub,
      );
      // Eve uses a different shared secret
      final eve = DoubleRatchet.initAsReceiver(
        sharedSecret: Uint8List.fromList(List.generate(32, (i) => 255 - i)),
        ratchetPublicKey: bobPub,
        ratchetPrivateKey: bobPriv,
      );

      final ad = Uint8List.fromList(utf8.encode('test'));
      final (_, msg) = await DoubleRatchet.encrypt(
        state: alice,
        plaintext: Uint8List.fromList(utf8.encode('secret')),
        associatedData: ad,
      );

      expect(
        () => DoubleRatchet.decrypt(state: eve, message: msg, associatedData: ad),
        throwsA(anything),
      );
    });

    test('tampered ciphertext fails', () async {
      final alice = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: bobPub,
      );
      final bob = DoubleRatchet.initAsReceiver(
        sharedSecret: sharedSecret,
        ratchetPublicKey: bobPub,
        ratchetPrivateKey: bobPriv,
      );

      final ad = Uint8List.fromList(utf8.encode('test'));
      final (_, msg) = await DoubleRatchet.encrypt(
        state: alice,
        plaintext: Uint8List.fromList(utf8.encode('original')),
        associatedData: ad,
      );

      // Tamper with ciphertext
      final tampered = Uint8List.fromList(msg.ciphertext.ciphertext);
      tampered[0] ^= 0xFF;
      final tamperedMsg = msg.copyWithTamperedCiphertext(tampered);

      expect(
        () => DoubleRatchet.decrypt(
            state: bob, message: tamperedMsg, associatedData: ad),
        throwsA(anything),
      );
    });

    test('RatchetState serialization roundtrip', () async {
      final state = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: bobPub,
      );

      final map = state.toMap();
      final restored = RatchetState.fromMap(map);

      expect(base64Encode(restored.rootKey), base64Encode(state.rootKey));
      expect(restored.sendMessageNumber, state.sendMessageNumber);
      expect(restored.receiveMessageNumber, state.receiveMessageNumber);
    });

    test('each message produces different ciphertext (nonce uniqueness)', () async {
      var alice = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: bobPub,
      );

      final ad = Uint8List.fromList(utf8.encode('test'));
      final pt = Uint8List.fromList(utf8.encode('same message'));

      final ciphertexts = <String>[];
      for (var i = 0; i < 5; i++) {
        final (a2, msg) = await DoubleRatchet.encrypt(
          state: alice, plaintext: pt, associatedData: ad);
        alice = a2;
        ciphertexts.add(base64Encode(msg.ciphertext.ciphertext));
      }

      // All ciphertexts should be different
      expect(ciphertexts.toSet().length, 5);
    });
  });

  group('DoubleRatchet — C1 regression (root key isolation)', () {
    test('initAsReceiver must not alias sharedSecret into state.rootKey',
        () async {
      final secret = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final expected = Uint8List.fromList(secret);

      final kp = await X25519().newKeyPair();
      final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
      final priv = Uint8List.fromList(await kp.extractPrivateKeyBytes());

      final state = DoubleRatchet.initAsReceiver(
        sharedSecret: secret,
        ratchetPublicKey: pub,
        ratchetPrivateKey: priv,
      );

      // Caller zeros its sharedSecret buffer after handing ownership
      // to the ratchet (mirrors session_handshake_service.dart flow).
      for (var i = 0; i < secret.length; i++) {
        secret[i] = 0;
      }

      expect(state.rootKey, orderedEquals(expected),
          reason: 'state.rootKey must not be aliased to the caller\'s buffer');
    });

    test(
        'first inbound message decrypts after caller zeros sharedSecret '
        '(end-to-end regression)', () async {
      final secret = Uint8List.fromList(List.generate(32, (i) => 42));
      final aliceSecret = Uint8List.fromList(secret);

      final kp = await X25519().newKeyPair();
      final bobPub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
      final bobPriv = Uint8List.fromList(await kp.extractPrivateKeyBytes());

      final alice = await DoubleRatchet.initAsSender(
        sharedSecret: aliceSecret,
        recipientRatchetPublicKey: bobPub,
      );
      final bob = DoubleRatchet.initAsReceiver(
        sharedSecret: secret,
        ratchetPublicKey: bobPub,
        ratchetPrivateKey: bobPriv,
      );

      // Simulate the exact caller pattern in session_handshake_service.dart:
      // zero the sharedSecret buffer after initAsReceiver returns.
      for (var i = 0; i < secret.length; i++) {
        secret[i] = 0;
      }

      final ad = Uint8List.fromList(utf8.encode('ad'));
      final pt = Uint8List.fromList(utf8.encode('first message'));

      final (_, msg) = await DoubleRatchet.encrypt(
        state: alice,
        plaintext: pt,
        associatedData: ad,
      );

      final (_, decrypted) = await DoubleRatchet.decrypt(
        state: bob,
        message: msg,
        associatedData: ad,
      );

      expect(utf8.decode(decrypted), 'first message');
    });

    test('initAsReceiver must not alias ratchetPrivateKey into state',
        () async {
      final secret = Uint8List.fromList(List.generate(32, (i) => i));
      final kp = await X25519().newKeyPair();
      final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
      final priv = Uint8List.fromList(await kp.extractPrivateKeyBytes());
      final expectedPriv = Uint8List.fromList(priv);

      final state = DoubleRatchet.initAsReceiver(
        sharedSecret: secret,
        ratchetPublicKey: pub,
        ratchetPrivateKey: priv,
      );

      for (var i = 0; i < priv.length; i++) {
        priv[i] = 0;
      }

      expect(state.dhSendingPrivate, orderedEquals(expectedPriv),
          reason:
              'state.dhSendingPrivate must not be aliased to the caller\'s buffer');
    });

    test('initAsSender must not alias recipientRatchetPublicKey into state',
        () async {
      final secret = Uint8List.fromList(List.generate(32, (i) => i));
      final kp = await X25519().newKeyPair();
      final recipientPub =
          Uint8List.fromList((await kp.extractPublicKey()).bytes);
      final expectedPub = Uint8List.fromList(recipientPub);

      final state = await DoubleRatchet.initAsSender(
        sharedSecret: secret,
        recipientRatchetPublicKey: recipientPub,
      );

      for (var i = 0; i < recipientPub.length; i++) {
        recipientPub[i] = 0;
      }

      expect(state.dhReceivingPublic, orderedEquals(expectedPub),
          reason:
              'state.dhReceivingPublic must not be aliased to the caller\'s buffer');
    });
  });
}

extension _TamperExt on RatchetMessage {
  RatchetMessage copyWithTamperedCiphertext(Uint8List tampered) {
    return RatchetMessage(
      header: header,
      ciphertext: EncryptedRatchetMessage(
        ciphertext: tampered,
        nonce: ciphertext.nonce,
        mac: ciphertext.mac,
      ),
    );
  }
}
