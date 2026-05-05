// Audit 2026-05 / Run 1 (Cryptography) — Finding H2-Crypto.
//
// Schwachstelle:
//   `EncryptionService.encryptLocal` / `decryptLocal` use XChaCha20-Poly1305
//   without AAD. The encrypted blob is therefore not bound to the storage
//   slot it lives in. An attacker with filesystem write access can swap
//   `ratchet_chatA.enc` and `ratchet_chatB.enc` (or `msg_*.enc`,
//   `contacts.enc`, etc.) — both decrypt successfully under the same
//   storage key, but each chat now sees the other's persisted state →
//   crypto-state corruption, broken sessions, possible cross-chat
//   plaintext disclosure.
//
// Fix:
//   Add `aad` parameter to encryptLocal/decryptLocal. Use the storage slot
//   name (e.g. `ratchet_<chatId>`) as AAD when the caller is the encrypted
//   store. Output format gets a leading version byte so legacy v1 blobs
//   (no AAD) remain readable.
//
// PoC-Status (vor Fix):
//   Test A — RED  (cross-slot decrypt succeeds)
//
// PoC-Status (nach Fix):
//   Test A — GREEN (cross-slot decrypt fails with AAD mismatch)
//   Test B — GREEN (back-compat: legacy blobs still decrypt)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/encryption/encryption_service.dart';

void main() {
  final svc = EncryptionService();
  final key = Uint8List.fromList(List.generate(32, (i) => i + 1));

  group('H2-Crypto: at-rest AAD binding', () {
    test('A — encryptLocal MUST bind ciphertext to its storage slot', () async {
      // Two different chats persist their ratchet state under different slot
      // names. Both encrypts use the same storage key.
      final ratchetA = Uint8List.fromList(List.filled(64, 0xAA));
      final ratchetB = Uint8List.fromList(List.filled(64, 0xBB));

      final encA = await svc.encryptLocal(
        plaintext: ratchetA,
        key: key,
        aad: 'ratchet_chatA',
      );
      final encB = await svc.encryptLocal(
        plaintext: ratchetB,
        key: key,
        aad: 'ratchet_chatB',
      );

      // Sanity: same-slot decrypt works.
      final roundA = await svc.decryptLocal(
          encrypted: encA, key: key, aad: 'ratchet_chatA');
      expect(roundA, equals(ratchetA));

      // Cross-slot decrypt MUST fail (attacker swapped files on disk).
      // Pre-fix: succeeds because no AAD binding.
      // Post-fix: throws because AAD mismatch invalidates the AEAD MAC.
      expect(
        () async => svc.decryptLocal(
            encrypted: encA, key: key, aad: 'ratchet_chatB'),
        throwsA(anything),
        reason:
            'cross-slot decrypt must fail — AAD must bind ciphertext to its '
            'logical storage slot so file swaps on disk cannot mix chat state',
      );
      expect(
        () async => svc.decryptLocal(
            encrypted: encB, key: key, aad: 'ratchet_chatA'),
        throwsA(anything),
      );
    });

    test('B — back-compat: legacy v1 blobs (no AAD) still decrypt', () async {
      // Pre-fix encryptLocal output is the legacy format. We simulate it by
      // calling encryptLocal without aad, then decrypting without aad.
      // The fix MUST keep this path working so existing on-disk data does
      // not become unreadable after upgrade.
      final plaintext =
          Uint8List.fromList(List.generate(128, (i) => (i * 37) & 0xFF));

      final encryptedLegacy = await svc.encryptLocal(
        plaintext: plaintext,
        key: key,
        // no aad → legacy format
      );
      final decrypted = await svc.decryptLocal(
        encrypted: encryptedLegacy,
        key: key,
        // no aad → legacy decrypt
      );
      expect(decrypted, equals(plaintext));
    });

    test('C — v2 blob (with AAD) cannot be decrypted as legacy', () async {
      // Defensive: an attacker who tries to "downgrade" by stripping AAD on
      // a v2 blob must not succeed. AAD-bound MAC fails if the version byte
      // or the AAD path is wrong.
      final plaintext = Uint8List.fromList(List.filled(48, 0x42));
      final encryptedV2 = await svc.encryptLocal(
        plaintext: plaintext,
        key: key,
        aad: 'some_slot',
      );

      // Try to decrypt without AAD (= legacy path).
      expect(
        () async => svc.decryptLocal(encrypted: encryptedV2, key: key),
        throwsA(anything),
        reason:
            'v2 blob decrypted without AAD must fail — no silent downgrade',
      );
    });
  });
}
