import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'ratchet_message.dart';
import 'ratchet_state.dart';

/// Signal Double Ratchet implementation.
///
/// Provides:
/// - Forward Secrecy: past message keys cannot be derived from current state
/// - Post-Compromise Security: after a break-in, security is restored on next DH ratchet
/// - Out-of-order message handling via skipped message key store
///
/// Cipher suite: X25519 DH, HKDF-SHA256, HMAC-SHA256, XChaCha20-Poly1305
class DoubleRatchet {
  static final _x25519 = X25519();
  static final _cipher = Xchacha20.poly1305Aead();
  static final _hmac = Hmac.sha256();

  /// Maximum number of messages to skip (prevents DoS via huge skip).
  static const _maxSkip = 1000;

  // ─── Session Initialization ────────────────────────────────────────────────

  /// Initialize as the sender (Alice) of the first message.
  ///
  /// [sharedSecret] is derived from X3DH or a simpler ECDH key agreement.
  /// [recipientRatchetPublicKey] is the recipient's initial ratchet public key.
  static Future<RatchetState> initAsSender({
    required Uint8List sharedSecret,
    required Uint8List recipientRatchetPublicKey,
  }) async {
    final dhKeyPair = await _x25519.newKeyPair();
    final dhPublic = Uint8List.fromList((await dhKeyPair.extractPublicKey()).bytes);
    final dhPrivate = Uint8List.fromList(await dhKeyPair.extractPrivateKeyBytes());

    final dhOut = await _dh(dhPrivate, recipientRatchetPublicKey);
    final (newRootKey, sendingChainKey) = await _kdfRootKey(sharedSecret, dhOut);

    return RatchetState(
      rootKey: newRootKey,
      sendingChainKey: sendingChainKey,
      dhSendingPublic: dhPublic,
      dhSendingPrivate: dhPrivate,
      dhReceivingPublic: recipientRatchetPublicKey,
    );
  }

  /// Initialize as the receiver (Bob) of the first message.
  ///
  /// [sharedSecret] is the same value Alice used.
  /// Bob's ratchet key pair comes from the prekey or identity key.
  static RatchetState initAsReceiver({
    required Uint8List sharedSecret,
    required Uint8List ratchetPublicKey,
    required Uint8List ratchetPrivateKey,
  }) {
    return RatchetState(
      rootKey: sharedSecret,
      dhSendingPublic: ratchetPublicKey,
      dhSendingPrivate: ratchetPrivateKey,
    );
  }

  // ─── Encrypt ───────────────────────────────────────────────────────────────

  /// Encrypt [plaintext] and advance the sending ratchet.
  ///
  /// Returns updated state and the ratchet message to transmit.
  static Future<(RatchetState, RatchetMessage)> encrypt({
    required RatchetState state,
    required Uint8List plaintext,
    required Uint8List associatedData,
  }) async {
    var s = state;

    // If no sending chain key, perform DH ratchet step first
    if (s.sendingChainKey == null) {
      s = await _dhRatchetSend(s);
    }

    final (newChainKey, messageKey) = await _kdfChainKey(s.sendingChainKey!);

    final header = RatchetHeader(
      dhPublicKey: s.dhSendingPublic,
      messageNumber: s.sendMessageNumber,
      previousChainLength: s.previousChainLength,
    );

    final ad = _concat(associatedData, header.toBytes());
    final encrypted = await _encryptWithKey(messageKey, plaintext, ad);

    return (
      s.copyWith(
        sendingChainKey: newChainKey,
        sendMessageNumber: s.sendMessageNumber + 1,
      ),
      RatchetMessage(header: header, ciphertext: encrypted),
    );
  }

  // ─── Decrypt ───────────────────────────────────────────────────────────────

  /// Decrypt a received [message] and advance the receiving ratchet.
  ///
  /// Returns updated state and plaintext bytes.
  static Future<(RatchetState, Uint8List)> decrypt({
    required RatchetState state,
    required RatchetMessage message,
    required Uint8List associatedData,
  }) async {
    var s = state;
    final header = message.header;

    // Try skipped message keys first (out-of-order delivery)
    final skippedKey = '${base64Encode(header.dhPublicKey)}:${header.messageNumber}';
    if (s.skippedMessageKeys.containsKey(skippedKey)) {
      final mk = s.skippedMessageKeys[skippedKey]!;
      final newSkipped = Map<String, Uint8List>.from(s.skippedMessageKeys)
        ..remove(skippedKey);
      final ad = _concat(associatedData, header.toBytes());
      final plaintext = await _decryptWithKey(mk, message.ciphertext, ad);
      return (s.copyWith(skippedMessageKeys: newSkipped), plaintext);
    }

    // DH ratchet step if sender's key changed
    final needsDhStep = s.dhReceivingPublic == null ||
        !_bytesEqual(header.dhPublicKey, s.dhReceivingPublic!);

    if (needsDhStep) {
      s = await _skipMessageKeys(s, header.previousChainLength);
      s = await _dhRatchetReceive(s, header.dhPublicKey);
    }

    s = await _skipMessageKeys(s, header.messageNumber);

    final (newChainKey, messageKey) = await _kdfChainKey(s.receivingChainKey!);
    s = s.copyWith(
      receivingChainKey: newChainKey,
      receiveMessageNumber: s.receiveMessageNumber + 1,
    );

    final ad = _concat(associatedData, header.toBytes());
    final plaintext = await _decryptWithKey(messageKey, message.ciphertext, ad);
    return (s, plaintext);
  }

  // ─── DH Ratchet Steps ─────────────────────────────────────────────────────

  /// Advance the sending ratchet: generate new DH key pair, derive new chain keys.
  static Future<RatchetState> _dhRatchetSend(RatchetState s) async {
    final kp = await _x25519.newKeyPair();
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final priv = Uint8List.fromList(await kp.extractPrivateKeyBytes());

    final dhOut = await _dh(priv, s.dhReceivingPublic!);
    final (newRk, ck) = await _kdfRootKey(s.rootKey, dhOut);

    return s.copyWith(
      rootKey: newRk,
      sendingChainKey: ck,
      dhSendingPublic: pub,
      dhSendingPrivate: priv,
      previousChainLength: s.sendMessageNumber,
      sendMessageNumber: 0,
    );
  }

  /// Advance receiving ratchet on new remote DH key.
  static Future<RatchetState> _dhRatchetReceive(
      RatchetState s, Uint8List remotePub) async {
    // Derive receiving chain key from current sending key + new remote key
    final dhOut1 = await _dh(s.dhSendingPrivate, remotePub);
    final (rk1, ckr) = await _kdfRootKey(s.rootKey, dhOut1);

    // Generate fresh sending DH key pair for response
    final kp = await _x25519.newKeyPair();
    final newPub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final newPriv = Uint8List.fromList(await kp.extractPrivateKeyBytes());

    final dhOut2 = await _dh(newPriv, remotePub);
    final (rk2, cks) = await _kdfRootKey(rk1, dhOut2);

    return s.copyWith(
      rootKey: rk2,
      receivingChainKey: ckr,
      sendingChainKey: cks,
      dhSendingPublic: newPub,
      dhSendingPrivate: newPriv,
      dhReceivingPublic: remotePub,
      previousChainLength: s.sendMessageNumber,
      sendMessageNumber: 0,
      receiveMessageNumber: 0,
    );
  }

  /// Store skipped message keys up to [until] in the receiving chain.
  /// Prunes oldest entries if total exceeds [_maxSkip] to prevent unbounded growth.
  static Future<RatchetState> _skipMessageKeys(
      RatchetState s, int until) async {
    if (s.receiveMessageNumber + _maxSkip < until) {
      throw StateError(
          'Too many skipped messages: $until (max $_maxSkip)');
    }
    if (s.receivingChainKey == null) return s;

    var state = s;
    while (state.receiveMessageNumber < until) {
      final (newCk, mk) = await _kdfChainKey(state.receivingChainKey!);
      final key =
          '${base64Encode(state.dhReceivingPublic!)}:${state.receiveMessageNumber}';
      final newSkipped =
          Map<String, Uint8List>.from(state.skippedMessageKeys)..[key] = mk;
      // Prune oldest entries if exceeding max
      while (newSkipped.length > _maxSkip) {
        newSkipped.remove(newSkipped.keys.first);
      }
      state = state.copyWith(
        receivingChainKey: newCk,
        receiveMessageNumber: state.receiveMessageNumber + 1,
        skippedMessageKeys: newSkipped,
      );
    }
    return state;
  }

  // ─── KDF Functions ─────────────────────────────────────────────────────────

  /// KDF_RK: HKDF-SHA256(salt=rk, ikm=dhOutput) → (new_rk 32B, ck 32B)
  static Future<(Uint8List, Uint8List)> _kdfRootKey(
      Uint8List rk, Uint8List dhOutput) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(dhOutput),
      nonce: rk,
      info: utf8.encode('KryptaDoubleRatchet-v1'),
    );
    final bytes = Uint8List.fromList(await derived.extractBytes());
    return (bytes.sublist(0, 32), bytes.sublist(32, 64));
  }

  /// KDF_CK: HMAC-SHA256(ck, 0x01) → message key; HMAC-SHA256(ck, 0x02) → new chain key
  static Future<(Uint8List, Uint8List)> _kdfChainKey(Uint8List ck) async {
    final mk = Uint8List.fromList(
        (await _hmac.calculateMac([0x01], secretKey: SecretKey(ck))).bytes);
    final newCk = Uint8List.fromList(
        (await _hmac.calculateMac([0x02], secretKey: SecretKey(ck))).bytes);
    return (newCk, mk);
  }

  // ─── Crypto Helpers ────────────────────────────────────────────────────────

  static Future<Uint8List> _dh(
      Uint8List privateKey, Uint8List publicKey) async {
    final kp = await _x25519.newKeyPairFromSeed(privateKey);
    final shared = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );
    return Uint8List.fromList(await shared.extractBytes());
  }

  static Future<EncryptedRatchetMessage> _encryptWithKey(
      Uint8List mk, Uint8List plaintext, Uint8List ad) async {
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(mk),
      aad: ad,
    );
    return EncryptedRatchetMessage(
      ciphertext: Uint8List.fromList(box.cipherText),
      nonce: Uint8List.fromList(box.nonce),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  static Future<Uint8List> _decryptWithKey(
      Uint8List mk, EncryptedRatchetMessage msg, Uint8List ad) async {
    final box = SecretBox(msg.ciphertext, nonce: msg.nonce, mac: Mac(msg.mac));
    return Uint8List.fromList(
      await _cipher.decrypt(box, secretKey: SecretKey(mk), aad: ad),
    );
  }

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final r = Uint8List(a.length + b.length);
    r.setRange(0, a.length, a);
    r.setRange(a.length, r.length, b);
    return r;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Generate an initial shared secret from two X25519 key pairs (simplified X3DH).
  ///
  /// Used when no prekey bundle is available.
  /// DH(sender_ephemeral_priv, recipient_identity_pub) XOR'd with
  /// DH(sender_identity_priv, recipient_identity_pub) → HKDF → 32 bytes
  static Future<Uint8List> deriveInitialSharedSecret({
    required Uint8List senderEphemeralPrivate,
    required Uint8List senderIdentityPrivate,
    required Uint8List recipientIdentityPublic,
  }) async {
    final dh1 = await _dh(senderEphemeralPrivate, recipientIdentityPublic);
    final dh2 = await _dh(senderIdentityPrivate, recipientIdentityPublic);

    // Concatenate both DH outputs as IKM for HKDF
    final ikm = Uint8List(dh1.length + dh2.length)
      ..setRange(0, dh1.length, dh1)
      ..setRange(dh1.length, dh1.length + dh2.length, dh2);

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: Uint8List(32), // zero salt
      info: utf8.encode('KryptaSessionInit-v1'),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// Generate a fresh ephemeral X25519 key pair.
  static Future<(Uint8List pub, Uint8List priv)> generateEphemeralKeyPair() async {
    final kp = await _x25519.newKeyPair();
    return (
      Uint8List.fromList((await kp.extractPublicKey()).bytes),
      Uint8List.fromList(await kp.extractPrivateKeyBytes()),
    );
  }
}
