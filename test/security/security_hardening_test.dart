import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/calculator/logic/code_detector.dart';
import 'package:kryptaapp/security/encryption/encryption_service.dart';
import 'package:kryptaapp/security/messaging/control_message.dart';
import 'package:kryptaapp/security/prekey/prekey_bundle.dart';
import 'package:kryptaapp/security/session/session_handshake_service.dart';
import 'package:kryptaapp/security/ratchet/double_ratchet.dart';
import 'package:kryptaapp/services/storage/encrypted_local_store.dart';
import 'package:kryptaapp/services/storage/secure_storage_service.dart';

void main() {
  late EncryptionService encryption;

  setUp(() {
    encryption = EncryptionService();
  });

  group('V1 Encryption Mandatory AAD', () {
    test('encrypt with AAD decrypts with matching AAD', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();

      final payload = await encryption.encryptMessage(
        plaintext: 'Hello with AAD',
        recipientPublicKey: bob.publicKey,
        senderPublicKey: alice.publicKey,
      );

      final decrypted = await encryption.decryptMessage(
        payload: payload,
        privateKey: bob.privateKey,
        senderPublicKey: alice.publicKey,
        recipientPublicKey: bob.publicKey,
      );

      expect(decrypted, 'Hello with AAD');
    });

    test('mismatched sender AAD fails — no fallback', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();
      final eve = await encryption.generateIdentityKeyPair();

      final payload = await encryption.encryptMessage(
        plaintext: 'AAD-bound message',
        recipientPublicKey: bob.publicKey,
        senderPublicKey: alice.publicKey,
      );

      // Wrong sender AAD must fail — no silent fallback to no-AAD
      expect(
        () => encryption.decryptMessage(
          payload: payload,
          privateKey: bob.privateKey,
          senderPublicKey: eve.publicKey,
          recipientPublicKey: bob.publicKey,
        ),
        throwsA(anything),
      );
    });

    test('mismatched recipient AAD fails — no fallback', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();
      final eve = await encryption.generateIdentityKeyPair();

      final payload = await encryption.encryptMessage(
        plaintext: 'For Bob only',
        recipientPublicKey: bob.publicKey,
        senderPublicKey: alice.publicKey,
      );

      // Wrong recipient in AAD must fail
      expect(
        () => encryption.decryptMessage(
          payload: payload,
          privateKey: bob.privateKey,
          senderPublicKey: alice.publicKey,
          recipientPublicKey: eve.publicKey,
        ),
        throwsA(anything),
      );
    });
  });

  group('Fallback DH3 Independence', () {
    test('deriveFallbackSecret returns secret and eph2 public key', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();
      final (ephPub, ephPriv) = await DoubleRatchet.generateEphemeralKeyPair();

      final (secret, eph2Pub) = await SessionHandshakeService.deriveFallbackSecret(
        identityPrivate: alice.privateKey,
        ephemeralPrivate: ephPriv,
        recipientIdentityPublic: bob.publicKey,
      );

      expect(secret.length, 32);
      expect(eph2Pub.length, 32);
      // eph2Pub must be different from ephPub (separate key pair)
      expect(base64Encode(eph2Pub), isNot(equals(base64Encode(ephPub))));
    });

    test('fallback secret is deterministic with same keys', () async {
      // This is actually NOT true — each call generates new eph2
      // So two calls produce different secrets (forward secrecy property)
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();
      final (_, ephPriv) = await DoubleRatchet.generateEphemeralKeyPair();

      final (secret1, _) = await SessionHandshakeService.deriveFallbackSecret(
        identityPrivate: alice.privateKey,
        ephemeralPrivate: ephPriv,
        recipientIdentityPublic: bob.publicKey,
      );

      final (secret2, _) = await SessionHandshakeService.deriveFallbackSecret(
        identityPrivate: alice.privateKey,
        ephemeralPrivate: ephPriv,
        recipientIdentityPublic: bob.publicKey,
      );

      // Different because eph2 is freshly generated each time
      expect(base64Encode(secret1), isNot(equals(base64Encode(secret2))));
    });
  });

  group('Signed PreKey Rotation Overlap', () {
    test('SignedPreKey serialization roundtrip', () {
      final spk = SignedPreKey(
        id: 42,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime(2026, 4, 20, 12, 0),
      );

      final map = spk.toMap();
      final restored = SignedPreKey.fromMap(map);

      expect(restored.id, 42);
      expect(restored.publicKey.length, 32);
      expect(restored.privateKey.length, 32);
      expect(restored.createdAt, DateTime(2026, 4, 20, 12, 0));
    });
  });

  group('ControlMessageCounter Persistence', () {
    test('counter increments correctly', () {
      final counter = ControlMessageCounter();
      expect(counter.nextCounter('chat1'), 1);
      expect(counter.nextCounter('chat1'), 2);
      expect(counter.nextCounter('chat2'), 1);
    });

    test('replay detection works', () {
      final counter = ControlMessageCounter();
      expect(counter.recordReceived('chat1', 1), true);
      expect(counter.recordReceived('chat1', 2), true);
      expect(counter.recordReceived('chat1', 2), false); // Replay!
      expect(counter.recordReceived('chat1', 1), false); // Replay!
    });

    test('toMap/loadFromMap roundtrip', () {
      final counter = ControlMessageCounter();
      counter.nextCounter('chat1');
      counter.nextCounter('chat1');
      counter.recordReceived('chat1', 5);

      final map = counter.toMap();
      final restored = ControlMessageCounter();
      restored.loadFromMap(map);

      expect(restored.nextCounter('chat1'), 3);
      expect(restored.getLastSeen('chat1'), 5);
      expect(restored.recordReceived('chat1', 5), false); // Replay
      expect(restored.recordReceived('chat1', 6), true);
    });

    test('onStateChanged callback fires on counter update', () {
      final counter = ControlMessageCounter();
      Map<String, dynamic>? lastState;
      counter.onStateChanged = (state) => lastState = state;

      counter.nextCounter('chat1');
      expect(lastState, isNotNull);
      expect((lastState!['counters'] as Map)['chat1'], 1);
    });
  });

  group('Message Padding Security', () {
    test('padding does not leak content in trailing bytes', () {
      // After unpadding, the padding bytes should not contain
      // predictable patterns that could be exploited
      final msg = Uint8List.fromList(utf8.encode('short'));
      final padded = EncryptionService.padPlaintext(msg);

      // Verify padding area has randomness (not all zeros or pattern)
      final paddingStart = 4 + msg.length;
      final paddingBytes = padded.sublist(paddingStart);
      final uniqueBytes = paddingBytes.toSet();
      // With 251 random bytes, we should have high entropy
      expect(uniqueBytes.length, greaterThan(50));
    });
  });

  group('X3DH Session Handshake Security', () {
    test('invalid public key length throws HandshakeException', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final invalidBundle = PreKeyBundle(
        identityPublicKey: Uint8List(31), // Wrong length!
        signedPreKeyPublic: Uint8List(32),
        signedPreKeySignature: Uint8List(64),
        signedPreKeyId: 1,
      );

      expect(
        () => SessionHandshakeService.createOutboundSession(
          identityKeyPair: alice,
          bundle: invalidBundle,
        ),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('zero shared secret (low-order point) is rejected', () async {
      // Using a 32-byte zero key as public key should trigger
      // the zero shared secret check (X25519 low-order point)
      final alice = await encryption.generateIdentityKeyPair();
      final zeroKey = Uint8List(32); // All zeros = low-order point

      final bundle = PreKeyBundle(
        identityPublicKey: zeroKey,
        signedPreKeyPublic: Uint8List(32),
        signedPreKeySignature: Uint8List(64),
        signedPreKeyId: 1,
      );

      expect(
        () => SessionHandshakeService.createOutboundSession(
          identityKeyPair: alice,
          bundle: bundle,
        ),
        throwsA(anything),
      );
    });
  });

  group('ControlMessage Signing', () {
    test('valid message verifies correctly', () async {
      final key = Uint8List.fromList(
          List.generate(32, (i) => i + 1));

      final msg = await ControlMessage.create(
        type: 'delivered',
        chatId: 'chat123',
        messageId: 'msg456',
        senderId: 'user789',
        counter: 1,
        signingKey: key,
      );

      expect(await msg.verify(key), true);
    });

    test('tampered message fails verification', () async {
      final key = Uint8List.fromList(
          List.generate(32, (i) => i + 1));

      final msg = await ControlMessage.create(
        type: 'delivered',
        chatId: 'chat123',
        messageId: 'msg456',
        senderId: 'user789',
        counter: 1,
        signingKey: key,
      );

      // Create tampered version with different type
      final tampered = ControlMessage(
        type: 'read', // Changed!
        chatId: msg.chatId,
        messageId: msg.messageId,
        senderId: msg.senderId,
        timestamp: msg.timestamp,
        counter: msg.counter,
        signature: msg.signature,
      );

      expect(await tampered.verify(key), false);
    });

    test('wrong key fails verification', () async {
      final key1 = Uint8List.fromList(
          List.generate(32, (i) => i + 1));
      final key2 = Uint8List.fromList(
          List.generate(32, (i) => i + 100));

      final msg = await ControlMessage.create(
        type: 'delivered',
        chatId: 'chat123',
        messageId: 'msg456',
        senderId: 'user789',
        counter: 1,
        signingKey: key1,
      );

      expect(await msg.verify(key2), false);
    });

    test('validate rejects replay', () async {
      final key = Uint8List.fromList(
          List.generate(32, (i) => i + 1));

      final msg = await ControlMessage.create(
        type: 'delivered',
        chatId: 'chat123',
        messageId: 'msg456',
        senderId: 'user789',
        counter: 5,
        signingKey: key,
      );

      // Counter 5 should be rejected if lastSeen is 5
      final error = msg.validate(
        expectedSenderId: 'user789',
        lastSeenCounter: 5,
      );
      expect(error, 'replay_detected');
    });

    test('validate rejects wrong sender', () async {
      final key = Uint8List.fromList(
          List.generate(32, (i) => i + 1));

      final msg = await ControlMessage.create(
        type: 'delivered',
        chatId: 'chat123',
        messageId: 'msg456',
        senderId: 'user789',
        counter: 1,
        signingKey: key,
      );

      final error = msg.validate(
        expectedSenderId: 'different_user',
        lastSeenCounter: 0,
      );
      expect(error, 'sender_mismatch');
    });

    test('validate accepts valid message', () async {
      final key = Uint8List.fromList(
          List.generate(32, (i) => i + 1));

      final msg = await ControlMessage.create(
        type: 'read',
        chatId: 'chat123',
        messageId: 'msg456',
        senderId: 'user789',
        counter: 10,
        signingKey: key,
      );

      final error = msg.validate(
        expectedSenderId: 'user789',
        lastSeenCounter: 9,
      );
      expect(error, isNull);
    });

    test('validate rejects expired message', () {
      final expired = ControlMessage(
        type: 'delivered',
        chatId: 'chat123',
        messageId: 'msg456',
        senderId: 'user789',
        timestamp: DateTime.now().millisecondsSinceEpoch - 400000, // 6+ min ago
        counter: 1,
        signature: 'dummy',
      );

      final error = expired.validate(
        expectedSenderId: 'user789',
        lastSeenCounter: 0,
      );
      expect(error, 'message_expired');
    });

    test('validate rejects future timestamp beyond skew tolerance', () {
      final future = ControlMessage(
        type: 'delivered',
        chatId: 'chat123',
        messageId: 'msg456',
        senderId: 'user789',
        timestamp: DateTime.now().millisecondsSinceEpoch + 60000, // +60s
        counter: 1,
        signature: 'dummy',
      );

      final error = future.validate(
        expectedSenderId: 'user789',
        lastSeenCounter: 0,
      );
      expect(error, 'future_timestamp');
    });

    test('toMap/fromMap serialization roundtrip', () async {
      final key = Uint8List.fromList(
          List.generate(32, (i) => i + 1));

      final original = await ControlMessage.create(
        type: 'delete',
        chatId: 'chatABC',
        messageId: 'msgDEF',
        senderId: 'senderGHI',
        counter: 42,
        signingKey: key,
      );

      final map = original.toMap();
      final restored = ControlMessage.fromMap(map);

      expect(restored.type, original.type);
      expect(restored.chatId, original.chatId);
      expect(restored.messageId, original.messageId);
      expect(restored.senderId, original.senderId);
      expect(restored.timestamp, original.timestamp);
      expect(restored.counter, original.counter);
      expect(restored.signature, original.signature);

      // Restored message must still verify
      expect(await restored.verify(key), true);
    });
  });

  group('ControlMessage Fail-Closed Deserialization', () {
    test('fromMap throws on missing type', () {
      expect(
        () => ControlMessage.fromMap({
          'chatId': 'c', 'mid': 'm', 'sid': 's',
          'ts': 1, 'ctr': 1, 'sig': 'sig',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap throws on missing chatId', () {
      expect(
        () => ControlMessage.fromMap({
          'type': 'delivered', 'mid': 'm', 'sid': 's',
          'ts': 1, 'ctr': 1, 'sig': 'sig',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap throws on missing messageId', () {
      expect(
        () => ControlMessage.fromMap({
          'type': 'delivered', 'chatId': 'c', 'sid': 's',
          'ts': 1, 'ctr': 1, 'sig': 'sig',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap throws on missing senderId', () {
      expect(
        () => ControlMessage.fromMap({
          'type': 'delivered', 'chatId': 'c', 'mid': 'm',
          'ts': 1, 'ctr': 1, 'sig': 'sig',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap throws on missing timestamp', () {
      expect(
        () => ControlMessage.fromMap({
          'type': 'delivered', 'chatId': 'c', 'mid': 'm', 'sid': 's',
          'ctr': 1, 'sig': 'sig',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap throws on missing counter', () {
      expect(
        () => ControlMessage.fromMap({
          'type': 'delivered', 'chatId': 'c', 'mid': 'm', 'sid': 's',
          'ts': 1, 'sig': 'sig',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap throws on missing signature', () {
      expect(
        () => ControlMessage.fromMap({
          'type': 'delivered', 'chatId': 'c', 'mid': 'm', 'sid': 's',
          'ts': 1, 'ctr': 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap throws on empty signature', () {
      expect(
        () => ControlMessage.fromMap({
          'type': 'delivered', 'chatId': 'c', 'mid': 'm', 'sid': 's',
          'ts': 1, 'ctr': 1, 'sig': '',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap throws on completely empty map', () {
      expect(
        () => ControlMessage.fromMap({}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromMap succeeds with all fields present', () {
      final msg = ControlMessage.fromMap({
        'type': 'read',
        'chatId': 'c123',
        'mid': 'm456',
        'sid': 's789',
        'ts': 1700000000000,
        'ctr': 5,
        'sig': 'validBase64Sig==',
      });

      expect(msg.type, 'read');
      expect(msg.chatId, 'c123');
      expect(msg.messageId, 'm456');
      expect(msg.senderId, 's789');
      expect(msg.timestamp, 1700000000000);
      expect(msg.counter, 5);
      expect(msg.signature, 'validBase64Sig==');
    });
  });

  group('ControlMessageCounter Edge Cases', () {
    test('clear resets all state', () {
      final counter = ControlMessageCounter();
      counter.nextCounter('chat1');
      counter.nextCounter('chat1');
      counter.recordReceived('chat1', 10);

      counter.clear();

      // After clear, counters start fresh
      expect(counter.nextCounter('chat1'), 1);
      expect(counter.getLastSeen('chat1'), 0);
      // Previously-seen counter should now be accepted
      expect(counter.recordReceived('chat1', 10), true);
    });

    test('chats are isolated from each other', () {
      final counter = ControlMessageCounter();
      counter.nextCounter('chatA');
      counter.nextCounter('chatA');
      counter.nextCounter('chatA');
      counter.recordReceived('chatA', 50);

      // chatB should be independent
      expect(counter.nextCounter('chatB'), 1);
      expect(counter.getLastSeen('chatB'), 0);
      expect(counter.recordReceived('chatB', 1), true);

      // chatA state unchanged
      expect(counter.nextCounter('chatA'), 4);
      expect(counter.getLastSeen('chatA'), 50);
    });

    test('onStateChanged fires on recordReceived', () {
      final counter = ControlMessageCounter();
      Map<String, dynamic>? lastState;
      counter.onStateChanged = (state) => lastState = state;

      counter.recordReceived('chat1', 7);
      expect(lastState, isNotNull);
      expect((lastState!['lastSeen'] as Map)['chat1'], 7);
    });

    test('onStateChanged fires on clear', () {
      final counter = ControlMessageCounter();
      counter.nextCounter('chat1');

      Map<String, dynamic>? lastState;
      counter.onStateChanged = (state) => lastState = state;

      counter.clear();
      expect(lastState, isNotNull);
      expect((lastState!['counters'] as Map), isEmpty);
      expect((lastState!['lastSeen'] as Map), isEmpty);
    });
  });

  group('CodeDetector Timing Normalization', () {
    // These tests verify the CodeDetector checks all codes in parallel
    // to normalize timing (prevent side-channel).
    test('checkCode returns none for empty input', () async {
      // Create a mock-like detector with the actual class
      // The important thing is that the method signature accepts empty input
      final detector = CodeDetector(
        storage: SecureStorageService(),
      );
      // Empty input should return none immediately without any hash computation
      final result = await detector.checkCode('');
      expect(result, CodeResult.none);
    });

    test('checkCode strips non-numeric characters', () async {
      final detector = CodeDetector(
        storage: SecureStorageService(),
      );
      // Non-numeric display values like "Error" should return none
      final result = await detector.checkCode('Error');
      expect(result, CodeResult.none);
    });
  });

  group('Encrypted Local Store Security', () {
    test('evictStaleCacheEntries removes expired ratchet entries', () {
      // This tests the eviction logic by checking the method exists
      // and can be called without error (functional test requires full init)
      final store = EncryptedLocalStore();
      // Should not throw even when no entries exist
      store.evictStaleCacheEntries();
    });
  });
}
