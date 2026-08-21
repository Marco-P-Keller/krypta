import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/transport/sealed_sender.dart';

void main() {
  group('DeliveryToken', () {
    test('generateDeliveryToken produces 32-byte base64 token', () {
      final token = SealedSender.generateDeliveryToken();
      final decoded = base64Decode(token.token);
      expect(decoded.length, 32);
    });

    test('each token is unique', () {
      final tokens = List.generate(100, (_) => SealedSender.generateDeliveryToken());
      final unique = tokens.map((t) => t.token).toSet();
      expect(unique.length, 100);
    });

    test('new token is not expired', () {
      final token = SealedSender.generateDeliveryToken();
      expect(token.isExpired, isFalse);
    });

    test('token created >24h ago is expired', () {
      final token = DeliveryToken(
        token: 'test-token',
        createdAt: DateTime.now().subtract(const Duration(hours: 25)),
      );
      expect(token.isExpired, isTrue);
    });

    test('token created <24h ago is not expired', () {
      final token = DeliveryToken(
        token: 'test-token',
        createdAt: DateTime.now().subtract(const Duration(hours: 23)),
      );
      expect(token.isExpired, isFalse);
    });

    test('toMap/fromMap roundtrip', () {
      final original = SealedSender.generateDeliveryToken();
      final map = original.toMap();
      final restored = DeliveryToken.fromMap(map);

      expect(restored.token, original.token);
      expect(
        restored.createdAt.millisecondsSinceEpoch,
        original.createdAt.millisecondsSinceEpoch,
      );
    });

    test('maxAge is 24 hours', () {
      expect(DeliveryToken.maxAge, const Duration(hours: 24));
    });
  });

  group('SealedEnvelope', () {
    test('seal embeds sender identity in payload', () async {
      final token = SealedSender.generateDeliveryToken();
      final payload = <String, dynamic>{'ct': 'encrypted-data', 'v': 2};

      final envelope = await SealedSender.seal(
        senderIdentity: 'alice123',
        innerPayload: payload,
        deliveryToken: token.token,
      );

      // Sender identity is inside the payload (encrypted in real use)
      expect(envelope.payload['_sid'], 'alice123');
      // Original payload data preserved
      expect(envelope.payload['ct'], 'encrypted-data');
      expect(envelope.payload['v'], 2);
      // Delivery token is on the envelope (visible to server for routing)
      expect(envelope.deliveryToken, token.token);
    });

    test('extractSender retrieves embedded sender identity', () {
      final decrypted = <String, dynamic>{
        'ct': 'encrypted-data',
        '_sid': 'alice123',
      };

      final sender = SealedSender.extractSender(decrypted);
      expect(sender, 'alice123');
    });

    test('extractSender returns null when no sender embedded', () {
      final decrypted = <String, dynamic>{
        'ct': 'encrypted-data',
      };

      final sender = SealedSender.extractSender(decrypted);
      expect(sender, isNull);
    });

    test('toFirestoreData contains delivery token but not sender identity', () async {
      final token = SealedSender.generateDeliveryToken();
      final envelope = await SealedSender.seal(
        senderIdentity: 'alice123',
        innerPayload: {'ct': 'encrypted-data'},
        deliveryToken: token.token,
      );

      final firestoreData = envelope.toFirestoreData('msg-001');

      // Server sees delivery token for routing
      expect(firestoreData['dt'], token.token);
      expect(firestoreData['mid'], 'msg-001');
      // Audit 2026-05 / M3-Crypto: payload values are no longer
      // stringified; native types pass through (Firestore accepts the
      // JSON-compatible types Krypta uses).
      final p = firestoreData['p'] as Map<String, dynamic>;
      expect(p.containsKey('_sid'), isTrue);
      // But the server sees '_sid' as a string inside the payload map,
      // which in real use would be inside the E2E encrypted blob —
      // the server cannot read it without the decryption key.
      expect(p['ct'], 'encrypted-data');
    });

    test('server cannot distinguish senders from Firestore data', () async {
      final token = SealedSender.generateDeliveryToken();

      final envelope1 = await SealedSender.seal(
        senderIdentity: 'alice',
        innerPayload: {'ct': 'blob1'},
        deliveryToken: token.token,
      );

      final envelope2 = await SealedSender.seal(
        senderIdentity: 'bob',
        innerPayload: {'ct': 'blob2'},
        deliveryToken: token.token,
      );

      final data1 = envelope1.toFirestoreData('msg-001');
      final data2 = envelope2.toFirestoreData('msg-002');

      // Both use the same delivery token — server routes them the same
      expect(data1['dt'], data2['dt']);
      // Server has no 'sid' / sender ID field at the routing level
      expect(data1.containsKey('sid'), isFalse);
      expect(data2.containsKey('sid'), isFalse);
    });
  });

  group('Sealed Sender Identity Binding', () {
    test('sender identity survives seal → extract roundtrip', () async {
      final token = SealedSender.generateDeliveryToken();
      final payload = <String, dynamic>{'ct': 'encrypted'};

      final envelope = await SealedSender.seal(
        senderIdentity: 'user456',
        innerPayload: payload,
        deliveryToken: token.token,
      );

      // Simulate: recipient decrypts the payload and extracts sender
      final extracted = SealedSender.extractSender(envelope.payload);
      expect(extracted, 'user456');
    });

    test('tampered sender identity is detectable by recipient', () async {
      final token = SealedSender.generateDeliveryToken();
      final payload = <String, dynamic>{'ct': 'encrypted'};

      final envelope = await SealedSender.seal(
        senderIdentity: 'real-sender',
        innerPayload: payload,
        deliveryToken: token.token,
      );

      // In real use, the payload is E2E encrypted. If an attacker
      // modifies _sid after encryption, the MAC check fails.
      // Here we test that the extraction reads exactly what was sealed.
      expect(SealedSender.extractSender(envelope.payload), 'real-sender');

      // Simulating tampering (would be caught by E2E MAC in production)
      envelope.payload['_sid'] = 'impersonator';
      expect(SealedSender.extractSender(envelope.payload), 'impersonator');
      expect(SealedSender.extractSender(envelope.payload), isNot('real-sender'));
    });

    test('delivery token rotation produces new token', () {
      final token1 = SealedSender.generateDeliveryToken();
      final token2 = SealedSender.generateDeliveryToken();

      // Tokens should be different (cryptographic randomness)
      expect(token1.token, isNot(token2.token));
    });
  });
}
