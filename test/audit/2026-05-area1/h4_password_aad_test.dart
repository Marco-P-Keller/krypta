// Audit 2026-05 / Run 1 (Cryptography) — Finding H4-Crypto.
//
// Schwachstelle:
//   `EncryptionService.encryptWithPassword` produced a v2 blob with no AAD.
//   If two parties share a password (or a single attacker knows it), a
//   password-protected blob from chat A / message X could be replayed into
//   chat B / message Y — the recipient would unlock it with the same
//   password and see the wrong content credited to the wrong context.
//
// Fix:
//   v3 container with mandatory AAD (chatId|messageId on the messenger
//   call sites). v2 stays readable for back-compat; new writes always v3.

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/encryption/encryption_service.dart';

void main() {
  final svc = EncryptionService();

  group('H4-Crypto: password-message AAD binding', () {
    test('A — v3 blob from one (chat,msg) context cannot decrypt under another',
        () async {
      const password = 'CorrectHorseBatteryStaple-9!';
      const plaintext = 'top secret';

      final blob = await svc.encryptWithPassword(
        plaintext: plaintext,
        password: password,
        aad: 'chatA|msg-1',
      );

      // Same context → succeeds.
      final ok = await svc.decryptWithPassword(
        encryptedBase64: blob,
        password: password,
        aad: 'chatA|msg-1',
      );
      expect(ok, equals(plaintext));

      // Cross-message replay (same chat) → fails.
      final crossMsg = await svc.decryptWithPassword(
        encryptedBase64: blob,
        password: password,
        aad: 'chatA|msg-2',
      );
      expect(crossMsg, isNull,
          reason: 'cross-message replay must fail (different AAD)');

      // Cross-chat replay → fails.
      final crossChat = await svc.decryptWithPassword(
        encryptedBase64: blob,
        password: password,
        aad: 'chatB|msg-1',
      );
      expect(crossChat, isNull,
          reason: 'cross-chat replay must fail (different AAD)');
    });

    test('B — v3 blob without aad on decrypt is refused (no silent downgrade)',
        () async {
      const password = 'AnotherStrongPassphrase-42!';
      final blob = await svc.encryptWithPassword(
        plaintext: 'secret',
        password: password,
        aad: 'chatX|msg-7',
      );

      final res = await svc.decryptWithPassword(
        encryptedBase64: blob,
        password: password,
        // no aad
      );
      expect(res, isNull,
          reason: 'v3 blob requires AAD on decrypt');
    });

    test('C — back-compat: v2 blobs (no aad) still decrypt without aad',
        () async {
      const password = 'LegacyPasswordExample-8!';

      final v2Blob = await svc.encryptWithPassword(
        plaintext: 'hello legacy',
        password: password,
        // no aad → produces v2
      );

      final res = await svc.decryptWithPassword(
        encryptedBase64: v2Blob,
        password: password,
        // no aad → v2 path
      );
      expect(res, equals('hello legacy'));
    });
  });
}
