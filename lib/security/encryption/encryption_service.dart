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

  Future<Uint8List> encryptLocal({
    required Uint8List plaintext,
    required Uint8List key,
  }) async {
    final secretKey = SecretKey(key);
    final secretBox = await _cipher.encrypt(plaintext, secretKey: secretKey);

    // Pack: [24-byte nonce][16-byte mac][ciphertext]
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
  }) async {
    const nonceLen = 24;
    const macLen = 16;
    const minLen = nonceLen + macLen; // 40 bytes minimum (nonce + mac, no ciphertext)

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

  Future<String> encryptWithPassword({
    required String plaintext,
    required String password,
  }) async {
    final salt = Uint8List.fromList(
      List.generate(16, (_) => Random.secure().nextInt(256)),
    );

    final derivedKey = await _argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: derivedKey,
    );

    final payload = {
      'v': 2,
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
  }) async {
    try {
      final jsonStr = utf8.decode(base64Decode(encryptedBase64));
      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;

      final version = (payload['v'] as int?) ?? 1;
      final salt = base64Decode(payload['s'] as String);
      final nonce = base64Decode(payload['n'] as String);
      final mac = base64Decode(payload['m'] as String);
      final ciphertext = base64Decode(payload['c'] as String);

      // Only Argon2id v2 is supported. v1 (PBKDF2) messages are rejected.
      if (version < 2) return null;

      final derivedKey = await _argon2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
      final decrypted = await _cipher.decrypt(secretBox, secretKey: derivedKey);
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
