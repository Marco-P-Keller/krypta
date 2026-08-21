import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/encryption/encryption_service.dart';
import 'package:kryptaapp/security/encryption/key_pair_model.dart';

void main() {
  late EncryptionService encryption;

  setUp(() {
    encryption = EncryptionService();
  });

  group('Key Generation', () {
    test('generates unique key pairs', () async {
      final kp1 = await encryption.generateIdentityKeyPair();
      final kp2 = await encryption.generateIdentityKeyPair();
      expect(kp1.publicKeyBase64, isNot(equals(kp2.publicKeyBase64)));
      expect(kp1.privateKeyBase64, isNot(equals(kp2.privateKeyBase64)));
    });

    test('key pair has correct lengths', () async {
      final kp = await encryption.generateIdentityKeyPair();
      expect(kp.publicKey.length, 32);
      expect(kp.privateKey.length, 32);
    });

    test('local storage key is 32 bytes', () {
      final key = encryption.generateLocalStorageKey();
      expect(key.length, 32);
    });

    test('local storage keys are unique', () {
      final k1 = encryption.generateLocalStorageKey();
      final k2 = encryption.generateLocalStorageKey();
      expect(base64Encode(k1), isNot(equals(base64Encode(k2))));
    });
  });

  group('E2E Message Encryption', () {
    test('encrypt and decrypt roundtrip', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();

      final payload = await encryption.encryptMessage(
        plaintext: 'Hello Bob!',
        recipientPublicKey: bob.publicKey,
        senderPublicKey: alice.publicKey,
      );

      final decrypted = await encryption.decryptMessage(
        payload: payload,
        privateKey: bob.privateKey,
        senderPublicKey: alice.publicKey,
        recipientPublicKey: bob.publicKey,
      );

      expect(decrypted, 'Hello Bob!');
    });

    test('each encryption produces different ciphertext (ephemeral keys)', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();

      final p1 = await encryption.encryptMessage(
        plaintext: 'same',
        recipientPublicKey: bob.publicKey,
        senderPublicKey: alice.publicKey,
      );
      final p2 = await encryption.encryptMessage(
        plaintext: 'same',
        recipientPublicKey: bob.publicKey,
        senderPublicKey: alice.publicKey,
      );

      expect(base64Encode(p1.ciphertext), isNot(equals(base64Encode(p2.ciphertext))));
    });

    test('wrong key fails decryption', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();
      final eve = await encryption.generateIdentityKeyPair();

      final payload = await encryption.encryptMessage(
        plaintext: 'For Bob only',
        recipientPublicKey: bob.publicKey,
        senderPublicKey: alice.publicKey,
      );

      expect(
        () => encryption.decryptMessage(
          payload: payload,
          privateKey: eve.privateKey,
          senderPublicKey: alice.publicKey,
          recipientPublicKey: eve.publicKey,
        ),
        throwsA(anything),
      );
    });

    test('tampered ciphertext fails', () async {
      final alice = await encryption.generateIdentityKeyPair();
      final bob = await encryption.generateIdentityKeyPair();
      final payload = await encryption.encryptMessage(
        plaintext: 'test',
        recipientPublicKey: bob.publicKey,
        senderPublicKey: alice.publicKey,
      );

      final tampered = Uint8List.fromList(payload.ciphertext);
      tampered[0] ^= 0xFF;

      expect(
        () => encryption.decryptMessage(
          payload: payload.copyWith(ciphertext: tampered),
          privateKey: bob.privateKey,
          senderPublicKey: alice.publicKey,
          recipientPublicKey: bob.publicKey,
        ),
        throwsA(anything),
      );
    });
  });

  group('Local Storage Encryption', () {
    test('encrypt and decrypt roundtrip', () async {
      final key = encryption.generateLocalStorageKey();
      final plaintext = Uint8List.fromList(utf8.encode('local data'));

      final encrypted = await encryption.encryptLocal(plaintext: plaintext, key: key);
      final decrypted = await encryption.decryptLocal(encrypted: encrypted, key: key);

      expect(utf8.decode(decrypted), 'local data');
    });

    test('wrong key fails', () async {
      final key1 = encryption.generateLocalStorageKey();
      final key2 = encryption.generateLocalStorageKey();
      final plaintext = Uint8List.fromList(utf8.encode('secret'));

      final encrypted = await encryption.encryptLocal(plaintext: plaintext, key: key1);

      expect(
        () => encryption.decryptLocal(encrypted: encrypted, key: key2),
        throwsA(anything),
      );
    });
  });

  group('Message Padding (traffic analysis protection)', () {
    test('pad and unpad roundtrip', () {
      final original = Uint8List.fromList(utf8.encode('Hello World!'));
      final padded = EncryptionService.padPlaintext(original);
      final unpadded = EncryptionService.unpadPlaintext(padded);
      expect(utf8.decode(unpadded), 'Hello World!');
    });

    test('padded size is at least 256 bytes', () {
      final tiny = Uint8List.fromList(utf8.encode('hi'));
      final padded = EncryptionService.padPlaintext(tiny);
      expect(padded.length, 256);
    });

    test('padded size is power of 2', () {
      // 300 bytes content + 4 header = 304 → next power of 2 = 512
      final content = Uint8List(300);
      final padded = EncryptionService.padPlaintext(content);
      expect(padded.length, 512);
    });

    test('large message rounds up correctly', () {
      final content = Uint8List(1000);
      final padded = EncryptionService.padPlaintext(content);
      expect(padded.length, 1024); // 1004 → next pow2 = 1024
    });

    test('empty message pads to 256', () {
      final padded = EncryptionService.padPlaintext(Uint8List(0));
      expect(padded.length, 256);
      final unpadded = EncryptionService.unpadPlaintext(padded);
      expect(unpadded.length, 0);
    });

    test('different messages of same length produce same padded size', () {
      final a = EncryptionService.padPlaintext(
          Uint8List.fromList(utf8.encode('Hello')));
      final b = EncryptionService.padPlaintext(
          Uint8List.fromList(utf8.encode('World')));
      expect(a.length, equals(b.length));
    });

    test('padding bytes are random (not all zeros)', () {
      final short = Uint8List.fromList([1, 2, 3]);
      final padded = EncryptionService.padPlaintext(short);
      // Check that at least some bytes after the content are non-zero
      final tail = padded.sublist(7); // 4 header + 3 content = 7
      final nonZero = tail.where((b) => b != 0).length;
      expect(nonZero, greaterThan(0));
    });

    test('unpadPlaintext rejects too-short data', () {
      expect(
        () => EncryptionService.unpadPlaintext(Uint8List(3)),
        throwsFormatException,
      );
    });

    test('unpadPlaintext rejects invalid length prefix', () {
      final bad = Uint8List(256);
      // Write length = 999 (larger than remaining bytes)
      bad[0] = 0; bad[1] = 0; bad[2] = 3; bad[3] = 0xE7; // 999
      expect(
        () => EncryptionService.unpadPlaintext(bad),
        throwsFormatException,
      );
    });
  });

  group('Password-Protected Messages', () {
    test('v2 Argon2id encrypt/decrypt roundtrip', () async {
      final encrypted = await encryption.encryptWithPassword(
        plaintext: 'secret message',
        password: 'StrongP@ss1',
      );

      final decrypted = await encryption.decryptWithPassword(
        encryptedBase64: encrypted,
        password: 'StrongP@ss1',
      );

      expect(decrypted, 'secret message');
    });

    test('wrong password returns null', () async {
      final encrypted = await encryption.encryptWithPassword(
        plaintext: 'secret',
        password: 'correct',
      );

      final result = await encryption.decryptWithPassword(
        encryptedBase64: encrypted,
        password: 'wrong',
      );

      expect(result, isNull);
    });

    test('new encryption uses v2', () async {
      final encrypted = await encryption.encryptWithPassword(
        plaintext: 'test', password: 'pass');
      final json = utf8.decode(base64Decode(encrypted));
      final map = jsonDecode(json) as Map;
      expect(map['v'], 2);
    });
  });
}

extension _TamperPayload on EncryptedPayload {
  EncryptedPayload copyWith({Uint8List? ciphertext}) {
    return EncryptedPayload(
      ciphertext: ciphertext ?? this.ciphertext,
      nonce: nonce,
      mac: mac,
      ephemeralPublicKey: ephemeralPublicKey,
    );
  }
}
