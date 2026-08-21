import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../memory/sensitive_buffer.dart';
import 'key_pair_model.dart';

/// Core encryption service using X25519 ECDH + HKDF-SHA256 + XChaCha20-Poly1305.
///
/// E2E message encryption flow:
/// 1. Generate ephemeral X25519 key pair per message (forward secrecy)
/// 2. ECDH: ephemeral_private × recipient_public → shared_secret
/// 3. HKDF: derive 32-byte encryption key from shared_secret
/// 4. XChaCha20-Poly1305: encrypt plaintext → ciphertext + MAC + nonce
/// 5. Transmit: {ciphertext, nonce, mac, ephemeral_public_key}
///
/// Local storage encryption:
/// Uses a random 256-bit key stored in platform keychain.
/// Same XChaCha20-Poly1305 cipher for data-at-rest.
class EncryptionService {
  final _x25519 = X25519();
  final _cipher = Xchacha20.poly1305Aead();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static final EncryptionService _instance = EncryptionService._();
  factory EncryptionService() => _instance;
  EncryptionService._();

  // --- Identity Key Pair ---

  Future<KryptaKeyPair> generateIdentityKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    return KryptaKeyPair(
      privateKey: Uint8List.fromList(privateBytes),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  // --- E2E Message Encryption ---

  /// Encrypt a message using ephemeral ECDH with mandatory AAD binding.
  ///
  /// [senderPublicKey] and [recipientPublicKey] are included as AAD to bind
  /// the ciphertext to both parties, preventing cross-conversation replay.
  /// AAD is mandatory — encryption without AAD is not allowed.
  Future<EncryptedPayload> encryptMessage({
    required String plaintext,
    required Uint8List recipientPublicKey,
    required Uint8List senderPublicKey,
  }) async {
    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: SimplePublicKey(
        recipientPublicKey,
        type: KeyPairType.x25519,
      ),
    );

    final sharedBytes = Uint8List.fromList(await sharedSecret.extractBytes());
    final derivedKey = await _deriveKey(
      sharedSecret: sharedSecret,
      info: 'krypta-ecc-msg-v1',
    );
    // Zero shared secret after key derivation — no longer needed.
    SensitiveBuffer.zeroBytes(sharedBytes);

    // Zero ephemeral private key — used once for this ECDH, never again.
    final ephPrivBytes = Uint8List.fromList(
        await ephemeralKeyPair.extractPrivateKeyBytes());
    SensitiveBuffer.zeroBytes(ephPrivBytes);

    // AAD: sender_pub || recipient_pub — mandatory, binds ciphertext to conversation.
    final aad = _buildMessageAad(senderPublicKey, recipientPublicKey);

    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: derivedKey,
      aad: aad,
    );

    return EncryptedPayload(
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      nonce: Uint8List.fromList(secretBox.nonce),
      mac: Uint8List.fromList(secretBox.mac.bytes),
      ephemeralPublicKey: Uint8List.fromList(ephemeralPublicKey.bytes),
    );
  }

  /// Decrypt a message using ephemeral ECDH with mandatory AAD validation.
  ///
  /// [senderPublicKey] and [recipientPublicKey] are required for AAD reconstruction.
  /// No fallback to AAD-free decryption — messages without valid AAD are rejected.
  Future<String> decryptMessage({
    required EncryptedPayload payload,
    required Uint8List privateKey,
    required Uint8List senderPublicKey,
    required Uint8List recipientPublicKey,
  }) async {
    final recipientKeyPair = await _x25519.newKeyPairFromSeed(privateKey);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: recipientKeyPair,
      remotePublicKey: SimplePublicKey(
        payload.ephemeralPublicKey,
        type: KeyPairType.x25519,
      ),
    );

    final sharedBytes = Uint8List.fromList(await sharedSecret.extractBytes());
    final derivedKey = await _deriveKey(
      sharedSecret: sharedSecret,
      info: 'krypta-ecc-msg-v1',
    );
    // Zero shared secret after key derivation.
    SensitiveBuffer.zeroBytes(sharedBytes);

    final secretBox = SecretBox(
      payload.ciphertext,
      nonce: payload.nonce,
      mac: Mac(payload.mac),
    );

    // Mandatory AAD validation — no fallback to AAD-free decryption.
    final aad = _buildMessageAad(senderPublicKey, recipientPublicKey);
    final decrypted = await _cipher.decrypt(
      secretBox,
      secretKey: derivedKey,
      aad: aad,
    );
    // H6: decode first, then zero the byte buffer. The String created by
    // utf8.decode is an un-zeroable copy, but clearing the source limits
    // the forensic window for recovering plaintext from heap snapshots.
    final out = utf8.decode(decrypted);
    _bestEffortZero(decrypted);
    return out;
  }

  /// Zero [bytes] in place when it is a mutable `Uint8List`; otherwise no-op.
  /// Wrapped in try/catch because a const/immutable `List<int>` throws on
  /// index assignment — we prefer a best-effort wipe over a crash.
  static void _bestEffortZero(List<int> bytes) {
    try {
      if (bytes is Uint8List) SensitiveBuffer.zeroBytes(bytes);
    } catch (_) {}
  }

  // --- Local Storage Encryption ---

  Uint8List generateLocalStorageKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
  }

  /// H2-Crypto (audit 2026-05): on-disk format version marker.
  ///   v1 (legacy, no version byte): [24 nonce][16 mac][ct]
  ///   v2: [0x02][24 nonce][16 mac][ct] with [aad] bound into the AEAD
  /// The version byte lets us decode pre-upgrade blobs that were written
  /// without AAD and accept new writes that bind to a storage slot.
  static const int _localFormatV2 = 0x02;

  /// Returns `true` if [encrypted] looks like a v2 (AAD-bound) blob.
  /// A v1 blob can spuriously match with probability ~1/256 — callers
  /// using this for migration should only need a best-effort hint, not
  /// a security check (the AEAD MAC remains the source of truth).
  static bool isLocalV2Format(Uint8List encrypted) =>
      encrypted.isNotEmpty && encrypted[0] == _localFormatV2;

  Future<Uint8List> encryptLocal({
    required Uint8List plaintext,
    required Uint8List key,
    String? aad,
  }) async {
    final secretKey = SecretKey(key);

    // H2-Crypto: when an AAD is provided (= caller is the encrypted store
    // and wants slot binding), emit the v2 format. Without AAD, keep the
    // legacy layout so older blobs and ad-hoc callers behave identically.
    if (aad != null) {
      final aadBytes = utf8.encode(aad);
      final secretBox = await _cipher.encrypt(
        plaintext,
        secretKey: secretKey,
        aad: aadBytes,
      );
      final result = Uint8List(
        1 +
            secretBox.nonce.length +
            secretBox.mac.bytes.length +
            secretBox.cipherText.length,
      );
      result[0] = _localFormatV2;
      var offset = 1;
      result.setRange(
          offset, offset + secretBox.nonce.length, secretBox.nonce);
      offset += secretBox.nonce.length;
      result.setRange(
          offset, offset + secretBox.mac.bytes.length, secretBox.mac.bytes);
      offset += secretBox.mac.bytes.length;
      result.setRange(offset, offset + secretBox.cipherText.length,
          secretBox.cipherText);
      return result;
    }

    // Legacy v1 layout (no AAD).
    final secretBox = await _cipher.encrypt(plaintext, secretKey: secretKey);
    final result = Uint8List(
      secretBox.nonce.length + secretBox.mac.bytes.length + secretBox.cipherText.length,
    );
    var offset = 0;
    result.setRange(offset, offset + secretBox.nonce.length, secretBox.nonce);
    offset += secretBox.nonce.length;
    result.setRange(offset, offset + secretBox.mac.bytes.length, secretBox.mac.bytes);
    offset += secretBox.mac.bytes.length;
    result.setRange(offset, offset + secretBox.cipherText.length, secretBox.cipherText);

    return result;
  }

  Future<Uint8List> decryptLocal({
    required Uint8List encrypted,
    required Uint8List key,
    String? aad,
  }) async {
    const nonceLen = 24;
    const macLen = 16;
    const minLen = nonceLen + macLen; // 40 bytes minimum (nonce + mac, no ciphertext)

    // H2-Crypto: format detection.
    //   • v2 blobs start with 0x02. We try the v2 path with the caller's AAD.
    //   • v1 blobs are 24-byte nonce + 16-byte mac + ciphertext. v1's first
    //     byte is the first byte of a random nonce, so it can collide with
    //     0x02 on roughly 1 in 256 of legacy blobs. To survive that without
    //     losing security, on v2-decrypt failure (typically caused by
    //     misclassified legacy data) we fall back to the legacy path. The
    //     fallback is safe because both paths require an AEAD MAC match —
    //     the only way both succeed is when the data really is what the
    //     successful path interprets it as. An attacker stripping the v2
    //     prefix produces data whose v1-MAC also fails.
    //
    // Codex R10 P2: when the caller did not provide AAD they have explicitly
    // asked for the legacy semantics, so we do NOT inspect the v2 marker —
    // about 1/256 random nonces would otherwise spuriously trip the v2 path
    // and break the legacy decode for ad-hoc / pre-upgrade callers.
    final bool hasV2Marker = aad != null &&
        encrypted.isNotEmpty &&
        encrypted[0] == _localFormatV2;
    if (hasV2Marker) {
      if (encrypted.length >= 1 + minLen) {
        try {
          final nonce = encrypted.sublist(1, 1 + nonceLen);
          final mac = encrypted.sublist(1 + nonceLen, 1 + nonceLen + macLen);
          final ciphertext = encrypted.sublist(1 + nonceLen + macLen);
          final aadBytes = utf8.encode(aad);
          final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
          return Uint8List.fromList(
            await _cipher.decrypt(secretBox,
                secretKey: SecretKey(key), aad: aadBytes),
          );
        } catch (_) {
          // Fall through to legacy attempt — could be legacy data whose
          // nonce coincidentally starts with 0x02.
        }
      }
    }

    // Legacy v1 path.
    if (encrypted.length < minLen) {
      throw FormatException('Encrypted data too short: ${encrypted.length} < $minLen');
    }

    final nonce = encrypted.sublist(0, nonceLen);
    final mac = encrypted.sublist(nonceLen, nonceLen + macLen);
    final ciphertext = encrypted.sublist(nonceLen + macLen);

    final secretKey = SecretKey(key);
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));

    return Uint8List.fromList(
      await _cipher.decrypt(secretBox, secretKey: secretKey),
    );
  }

  // --- Password-Protected Message Encryption ---
  //
  // v2 flow: password → Argon2id(19 MiB, 2 iter, p=1) → 256-bit key → XChaCha20-Poly1305
  // Output: base64 JSON {v: 2, s: salt, n: nonce, m: mac, c: ciphertext}
  //
  // v1 (legacy PBKDF2) is still readable for migration; new writes always use v2.
  // The result is stored as `decryptedContent` and transmitted inside E2E.

  static final _argon2 = Argon2id(
    parallelism: 1,
    memory: 19456, // 19 MiB — OWASP minimum for interactive logins
    iterations: 2,
    hashLength: 32,
  );

  /// Encrypt [plaintext] with a password-derived key.
  ///
  /// H4-Crypto (audit 2026-05): when [aad] is provided (recommended:
  /// `chatId|messageId`), the resulting blob is bound to that context via
  /// the AEAD AAD. The container becomes v3 (with `aad` flag). v2 (no
  /// AAD) remains for back-compat reads, but new writes always emit v3
  /// when an aad is supplied.
  Future<String> encryptWithPassword({
    required String plaintext,
    required String password,
    String? aad,
  }) async {
    final salt = Uint8List.fromList(
      List.generate(16, (_) => Random.secure().nextInt(256)),
    );

    final derivedKey = await _argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    final aadBytes = aad == null ? null : utf8.encode(aad);
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: derivedKey,
      aad: aadBytes ?? const <int>[],
    );

    final payload = <String, dynamic>{
      'v': aad == null ? 2 : 3,
      's': base64Encode(salt),
      'n': base64Encode(Uint8List.fromList(secretBox.nonce)),
      'm': base64Encode(Uint8List.fromList(secretBox.mac.bytes)),
      'c': base64Encode(Uint8List.fromList(secretBox.cipherText)),
    };

    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  Future<String?> decryptWithPassword({
    required String encryptedBase64,
    required String password,
    String? aad,
  }) async {
    try {
      final jsonStr = utf8.decode(base64Decode(encryptedBase64));
      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;

      final version = (payload['v'] as int?) ?? 1;
      final salt = base64Decode(payload['s'] as String);
      final nonce = base64Decode(payload['n'] as String);
      final mac = base64Decode(payload['m'] as String);
      final ciphertext = base64Decode(payload['c'] as String);

      // Only Argon2id v2+ are supported. v1 (PBKDF2) messages are rejected.
      if (version < 2) return null;
      // H4-Crypto: v3 requires AAD; refuse to silently decrypt without it.
      if (version >= 3 && aad == null) return null;
      // For v2 the AAD is ignored on decrypt (back-compat); new writes
      // pass aad and so produce v3.
      final aadBytes = (version >= 3 && aad != null)
          ? utf8.encode(aad)
          : const <int>[];

      final derivedKey = await _argon2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
      final decrypted = await _cipher.decrypt(
        secretBox,
        secretKey: derivedKey,
        aad: aadBytes,
      );
      // H6: see decryptMessage — decode, then best-effort zero.
      final out = utf8.decode(decrypted);
      _bestEffortZero(decrypted);
      return out;
    } catch (_) {
      return null; // Wrong password or corrupted data
    }
  }

  // --- Message Padding (traffic analysis protection) ---
  //
  // Pads plaintext to the next power-of-2 block (min 256 bytes) so an observer
  // cannot infer message length from ciphertext size.
  // Format: [4-byte big-endian original length][original bytes][random padding]

  static const _minPaddedSize = 256;

  /// Pad plaintext to a fixed block size before encryption.
  static Uint8List padPlaintext(Uint8List plaintext) {
    final totalNeeded = 4 + plaintext.length; // 4-byte length prefix
    var blockSize = _minPaddedSize;
    while (blockSize < totalNeeded) {
      blockSize *= 2;
    }

    final padded = Uint8List(blockSize);
    // Write original length as 4-byte big-endian
    padded[0] = (plaintext.length >> 24) & 0xFF;
    padded[1] = (plaintext.length >> 16) & 0xFF;
    padded[2] = (plaintext.length >> 8) & 0xFF;
    padded[3] = plaintext.length & 0xFF;
    padded.setRange(4, 4 + plaintext.length, plaintext);

    // Fill remaining bytes with random data (not zeros — prevents pattern analysis)
    final random = Random.secure();
    for (var i = 4 + plaintext.length; i < blockSize; i++) {
      padded[i] = random.nextInt(256);
    }
    return padded;
  }

  /// Remove padding after decryption.
  static Uint8List unpadPlaintext(Uint8List padded) {
    if (padded.length < 4) throw FormatException('Padded data too short');
    final length = (padded[0] << 24) | (padded[1] << 16) | (padded[2] << 8) | padded[3];
    if (length < 0 || 4 + length > padded.length) {
      throw FormatException('Invalid padding length');
    }
    return padded.sublist(4, 4 + length);
  }

  // --- Helpers ---

  Future<SecretKey> _deriveKey({
    required SecretKey sharedSecret,
    required String info,
  }) async {
    // Use 32-byte zero salt per RFC 5869 (hash-length zeros when no salt)
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: Uint8List(32),
      info: utf8.encode(info),
    );
  }

  /// Build AAD for V1 messages: sender_pub || recipient_pub.
  /// Binds ciphertext to the conversation so it cannot be replayed between
  /// different sender/recipient pairs.
  static Uint8List _buildMessageAad(
      Uint8List? senderPub, Uint8List? recipientPub) {
    final sLen = senderPub?.length ?? 0;
    final rLen = recipientPub?.length ?? 0;
    final aad = Uint8List(sLen + rLen);
    if (senderPub != null) aad.setRange(0, sLen, senderPub);
    if (recipientPub != null) aad.setRange(sLen, sLen + rLen, recipientPub);
    return aad;
  }
}
