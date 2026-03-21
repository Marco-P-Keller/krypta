import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
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

  Future<EncryptedPayload> encryptMessage({
    required String plaintext,
    required Uint8List recipientPublicKey,
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

    final derivedKey = await _deriveKey(
      sharedSecret: sharedSecret,
      info: 'krypta-ecc-msg-v1',
    );

    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: derivedKey,
    );

    return EncryptedPayload(
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      nonce: Uint8List.fromList(secretBox.nonce),
      mac: Uint8List.fromList(secretBox.mac.bytes),
      ephemeralPublicKey: Uint8List.fromList(ephemeralPublicKey.bytes),
    );
  }

  Future<String> decryptMessage({
    required EncryptedPayload payload,
    required Uint8List privateKey,
  }) async {
    final recipientKeyPair = await _x25519.newKeyPairFromSeed(privateKey);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: recipientKeyPair,
      remotePublicKey: SimplePublicKey(
        payload.ephemeralPublicKey,
        type: KeyPairType.x25519,
      ),
    );

    final derivedKey = await _deriveKey(
      sharedSecret: sharedSecret,
      info: 'krypta-ecc-msg-v1',
    );

    final secretBox = SecretBox(
      payload.ciphertext,
      nonce: payload.nonce,
      mac: Mac(payload.mac),
    );

    final decrypted = await _cipher.decrypt(
      secretBox,
      secretKey: derivedKey,
    );

    return utf8.decode(decrypted);
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
  // Flow: password → PBKDF2(100k rounds) → 256-bit key → XChaCha20-Poly1305
  // Output: base64 JSON {s: salt, n: nonce, m: mac, c: ciphertext}
  // The result is stored as `decryptedContent` and transmitted inside E2E.

  Future<String> encryptWithPassword({
    required String plaintext,
    required String password,
  }) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    final derivedKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: derivedKey,
    );

    final payload = {
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

      final salt = base64Decode(payload['s'] as String);
      final nonce = base64Decode(payload['n'] as String);
      final mac = base64Decode(payload['m'] as String);
      final ciphertext = base64Decode(payload['c'] as String);

      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );

      final derivedKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
      final decrypted = await _cipher.decrypt(secretBox, secretKey: derivedKey);
      return utf8.decode(decrypted);
    } catch (_) {
      return null; // Wrong password or corrupted data
    }
  }

  // --- Helpers ---

  Future<SecretKey> _deriveKey({
    required SecretKey sharedSecret,
    required String info,
  }) async {
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: Uint8List(0),
      info: utf8.encode(info),
    );
  }
}
