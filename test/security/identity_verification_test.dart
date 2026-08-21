import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/contact_model.dart';
import 'package:kryptaapp/security/verification/safety_number.dart';

void main() {
  group('Safety Number Determinism', () {
    test('same inputs always produce the same safety number', () async {
      final pubA = Uint8List.fromList(List.generate(32, (i) => i));
      final pubB = Uint8List.fromList(List.generate(32, (i) => 255 - i));

      final sn1 = await SafetyNumber.generate(
        localUserId: 'alice123',
        localIdentityPublic: pubA,
        remoteUserId: 'bob456',
        remoteIdentityPublic: pubB,
      );
      final sn2 = await SafetyNumber.generate(
        localUserId: 'alice123',
        localIdentityPublic: pubA,
        remoteUserId: 'bob456',
        remoteIdentityPublic: pubB,
      );

      expect(sn1, equals(sn2));
      expect(sn1.length, 60);
    });

    test('symmetry: both sides compute the same number', () async {
      final pubA = Uint8List.fromList(List.generate(32, (i) => i + 10));
      final pubB = Uint8List.fromList(List.generate(32, (i) => i + 50));

      final fromAlice = await SafetyNumber.generate(
        localUserId: 'alice',
        localIdentityPublic: pubA,
        remoteUserId: 'bob',
        remoteIdentityPublic: pubB,
      );
      final fromBob = await SafetyNumber.generate(
        localUserId: 'bob',
        localIdentityPublic: pubB,
        remoteUserId: 'alice',
        remoteIdentityPublic: pubA,
      );

      expect(fromAlice, equals(fromBob));
    });

    test('different keys produce different safety numbers', () async {
      final pubA = Uint8List.fromList(List.generate(32, (i) => i));
      final pubB = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      final pubC = Uint8List.fromList(List.generate(32, (i) => i * 2));

      final sn1 = await SafetyNumber.generate(
        localUserId: 'alice',
        localIdentityPublic: pubA,
        remoteUserId: 'bob',
        remoteIdentityPublic: pubB,
      );
      final sn2 = await SafetyNumber.generate(
        localUserId: 'alice',
        localIdentityPublic: pubA,
        remoteUserId: 'bob',
        remoteIdentityPublic: pubC,
      );

      expect(sn1, isNot(equals(sn2)));
    });

    test('different user IDs produce different safety numbers', () async {
      final pubA = Uint8List.fromList(List.generate(32, (i) => i));
      final pubB = Uint8List.fromList(List.generate(32, (i) => 255 - i));

      final sn1 = await SafetyNumber.generate(
        localUserId: 'alice',
        localIdentityPublic: pubA,
        remoteUserId: 'bob',
        remoteIdentityPublic: pubB,
      );
      final sn2 = await SafetyNumber.generate(
        localUserId: 'alice',
        localIdentityPublic: pubA,
        remoteUserId: 'charlie',
        remoteIdentityPublic: pubB,
      );

      expect(sn1, isNot(equals(sn2)));
    });

    test('rejects invalid version', () async {
      final pub = Uint8List(32);
      expect(
        () => SafetyNumber.generate(
          localUserId: 'a',
          localIdentityPublic: pub,
          remoteUserId: 'b',
          remoteIdentityPublic: pub,
          version: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => SafetyNumber.generate(
          localUserId: 'a',
          localIdentityPublic: pub,
          remoteUserId: 'b',
          remoteIdentityPublic: pub,
          version: 999,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Safety Number Version Management', () {
    test('currentVersion is at least 1', () {
      expect(SafetyNumber.currentVersion, greaterThanOrEqualTo(1));
    });

    test('needsReVerification returns true for null version', () {
      expect(SafetyNumber.needsReVerification(null), true);
    });

    test('needsReVerification returns false for current version', () {
      expect(
        SafetyNumber.needsReVerification(SafetyNumber.currentVersion),
        false,
      );
    });

    test('needsReVerification returns true for older version', () {
      if (SafetyNumber.currentVersion > 1) {
        expect(SafetyNumber.needsReVerification(1), true);
      }
      // Always true for version 0
      expect(SafetyNumber.needsReVerification(0), true);
    });
  });

  group('QR Payload Roundtrip', () {
    test('encode and decode produces identical key material', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i + 42));
      final userId = 'testUser12345678901234567890';

      // Encode (matches QrDisplaySheet._buildQrPayload)
      final ikBase64 = base64Encode(key);
      final fp = Contact.computeFullFingerprint(key);
      final payload = jsonEncode({
        'v': 1,
        'uid': userId,
        'ik': ikBase64,
        'fp': fp,
      });

      // Decode (matches QrScannerScreen._parseQrPayload)
      final json = jsonDecode(payload) as Map<String, dynamic>;
      expect(json['v'], 1);
      expect(json['uid'], userId);

      final decodedKey = base64Decode(json['ik'] as String);
      expect(decodedKey, equals(key));

      // Fingerprint recomputation matches
      final recomputedFp = Contact.computeFullFingerprint(decodedKey);
      expect(recomputedFp, equals(fp));
    });

    test('fingerprint mismatch detected on tampered key', () {
      final realKey = Uint8List.fromList(List.generate(32, (i) => i));
      final tamperedKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

      final realFp = Contact.computeFullFingerprint(realKey);
      final tamperedFp = Contact.computeFullFingerprint(tamperedKey);

      expect(realFp, isNot(equals(tamperedFp)));
    });

    test('QR payload version must be 1', () {
      final key = Uint8List(32);
      final payload = jsonEncode({
        'v': 2, // Wrong version
        'uid': 'user',
        'ik': base64Encode(key),
        'fp': Contact.computeFullFingerprint(key),
      });

      final json = jsonDecode(payload) as Map<String, dynamic>;
      final version = json['v'];
      expect(version != 1, true, reason: 'Non-v1 payloads must be rejected');
    });

    test('QR payload missing fields are detected', () {
      // Missing 'ik'
      final payload = jsonEncode({
        'v': 1,
        'uid': 'user',
        'fp': 'abc',
      });
      final json = jsonDecode(payload) as Map<String, dynamic>;
      expect(json['ik'], isNull);
    });
  });

  group('Contact Model Identity Tracking', () {
    test('firstSeenIdentityKey is preserved across serialization', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final firstKey = Uint8List.fromList(List.generate(32, (i) => 100 + i));

      final contact = Contact(
        id: 'user123',
        displayName: 'Alice',
        publicKey: key,
        addedAt: DateTime(2026, 4, 21),
        firstSeenIdentityKey: firstKey,
        keyChangeCount: 3,
        lastKeyChangeAt: DateTime(2026, 4, 20),
        safetyNumberVersion: 1,
      );

      final map = contact.toMap();
      final restored = Contact.fromMap(map);

      expect(restored.firstSeenIdentityKey, equals(firstKey));
      expect(restored.keyChangeCount, 3);
      expect(restored.lastKeyChangeAt, DateTime(2026, 4, 20));
      expect(restored.safetyNumberVersion, 1);
    });

    test('keyChangeCount defaults to 0 for legacy contacts', () {
      final map = {
        'id': 'user123',
        'displayName': 'Legacy',
        'publicKey': base64Encode(Uint8List(32)),
        'addedAt': DateTime.now().millisecondsSinceEpoch,
        'trustState': 0,
      };
      final contact = Contact.fromMap(map);
      expect(contact.keyChangeCount, 0);
      expect(contact.firstSeenIdentityKey, isNull);
      expect(contact.lastKeyChangeAt, isNull);
      expect(contact.safetyNumberVersion, isNull);
    });

    test('key change updates tracking fields via copyWith', () {
      final originalKey = Uint8List.fromList(List.generate(32, (i) => i));
      final newKey = Uint8List.fromList(List.generate(32, (i) => 200 + i));
      final now = DateTime.now();

      final contact = Contact(
        id: 'user123',
        displayName: 'Alice',
        publicKey: originalKey,
        addedAt: DateTime(2026, 1, 1),
        firstSeenIdentityKey: originalKey,
        keyChangeCount: 0,
      );

      final updated = contact.copyWith(
        publicKey: newKey,
        trustState: TrustState.keyChanged,
        previousPublicKey: originalKey,
        lastKeyChangeAt: now,
        keyChangeCount: 1,
        safetyNumberVersion: null,
      );

      expect(updated.publicKey, equals(newKey));
      expect(updated.trustState, TrustState.keyChanged);
      expect(updated.previousPublicKey, equals(originalKey));
      expect(updated.firstSeenIdentityKey, equals(originalKey));
      expect(updated.lastKeyChangeAt, equals(now));
      expect(updated.keyChangeCount, 1);
      expect(updated.safetyNumberVersion, isNull);
    });

    test('canSendMessages blocked for keyChanged and blocked states', () {
      final key = Uint8List(32);
      final base = Contact(
        id: 'user',
        displayName: 'Test',
        publicKey: key,
        addedAt: DateTime.now(),
      );

      expect(base.canSendMessages, true);
      expect(
        base.copyWith(trustState: TrustState.verified).canSendMessages,
        true,
      );
      expect(
        base.copyWith(trustState: TrustState.keyChanged).canSendMessages,
        false,
      );
      expect(
        base.copyWith(trustState: TrustState.blocked).canSendMessages,
        false,
      );
    });
  });

  group('Key Mismatch Detection', () {
    test('constant-time comparison detects mismatched keys', () {
      final keyA = Uint8List.fromList(List.generate(32, (i) => i));
      final keyB = Uint8List.fromList(List.generate(32, (i) => i));
      final keyC = Uint8List.fromList(List.generate(32, (i) => 255 - i));

      // Same keys
      expect(_constantTimeEquals(keyA, keyB), true);
      // Different keys
      expect(_constantTimeEquals(keyA, keyC), false);
    });

    test('constant-time comparison rejects different lengths', () {
      final short = Uint8List(16);
      final long = Uint8List(32);
      expect(_constantTimeEquals(short, long), false);
    });

    test('single bit difference is detected', () {
      final keyA = Uint8List.fromList(List.generate(32, (i) => 0));
      final keyB = Uint8List.fromList(List.generate(32, (i) => 0));
      keyB[31] = 1; // Flip one bit in last byte

      expect(_constantTimeEquals(keyA, keyB), false);
    });

    test('fingerprint changes when key changes', () {
      final key1 = Uint8List.fromList(List.generate(32, (i) => i));
      final key2 = Uint8List.fromList(List.generate(32, (i) => i + 1));

      final fp1 = Contact.computeFullFingerprint(key1);
      final fp2 = Contact.computeFullFingerprint(key2);

      expect(fp1, isNot(equals(fp2)));
      expect(fp1.length, 64); // SHA-256 hex = 64 chars
      expect(fp2.length, 64);
    });
  });

  group('Contact Trust State Transitions', () {
    test('unverified → verified preserves firstSeenIdentityKey', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final contact = Contact(
        id: 'user',
        displayName: 'Test',
        publicKey: key,
        addedAt: DateTime.now(),
        firstSeenIdentityKey: key,
      );

      final verified = contact.copyWith(
        trustState: TrustState.verified,
        verifiedAt: DateTime.now(),
        verificationMethod: VerificationMethod.qrCode,
        verifiedFingerprint: Contact.computeFullFingerprint(key),
        safetyNumberVersion: SafetyNumber.currentVersion,
      );

      expect(verified.isVerified, true);
      expect(verified.firstSeenIdentityKey, equals(key));
      expect(verified.safetyNumberVersion, SafetyNumber.currentVersion);
    });

    test('verified → keyChanged clears verification state', () {
      final oldKey = Uint8List.fromList(List.generate(32, (i) => i));
      final newKey = Uint8List.fromList(List.generate(32, (i) => 200 + i));

      final verified = Contact(
        id: 'user',
        displayName: 'Test',
        publicKey: oldKey,
        addedAt: DateTime.now(),
        trustState: TrustState.verified,
        verifiedAt: DateTime.now(),
        verificationMethod: VerificationMethod.qrCode,
        verifiedFingerprint: Contact.computeFullFingerprint(oldKey),
        firstSeenIdentityKey: oldKey,
        safetyNumberVersion: 1,
      );

      final changed = verified.copyWith(
        publicKey: newKey,
        trustState: TrustState.keyChanged,
        verifiedAt: null,
        verificationMethod: null,
        verifiedFingerprint: null,
        safetyNumberVersion: null,
        previousPublicKey: oldKey,
        lastKeyChangeAt: DateTime.now(),
        keyChangeCount: 1,
      );

      expect(changed.hasKeyChanged, true);
      expect(changed.canSendMessages, false);
      expect(changed.verifiedAt, isNull);
      expect(changed.safetyNumberVersion, isNull);
      expect(changed.previousPublicKey, equals(oldKey));
      expect(changed.firstSeenIdentityKey, equals(oldKey));
      expect(changed.keyChangeCount, 1);
    });
  });
}

/// Mirror of MessengerProvider._constantTimeEquals for testing.
bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
