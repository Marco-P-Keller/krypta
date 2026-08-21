import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../memory/sensitive_buffer.dart';
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
  /// Signal reference uses 100-200; 200 balances security and usability.
  static const _maxSkip = 200;

  /// Maximum age for skipped message keys (7 days).
  /// Keys older than this are zeroed and pruned to preserve forward secrecy.
  /// Shorter window (vs. Signal's 30 days) reduces RAM/disk exposure.
  static const _maxSkipAge = Duration(days: 7);

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
    // Zero intermediate DH output — it's been consumed by KDF.
    SensitiveBuffer.zeroBytes(dhOut);

    return RatchetState(
      rootKey: newRootKey,
      sendingChainKey: sendingChainKey,
      dhSendingPublic: dhPublic,
      dhSendingPrivate: dhPrivate,
      dhReceivingPublic: Uint8List.fromList(recipientRatchetPublicKey),
    );
  }

  /// Initialize as the receiver (Bob) of the first message.
  ///
  /// [sharedSecret] is the same value Alice used.
  /// Bob's ratchet key pair comes from the prekey or identity key.
  ///
  /// All caller-supplied byte buffers ([sharedSecret], [ratchetPublicKey],
  /// [ratchetPrivateKey]) are copied into the state, so the caller may safely
  /// zero or reuse its own buffers after this returns without corrupting the
  /// session state.
  static RatchetState initAsReceiver({
    required Uint8List sharedSecret,
    required Uint8List ratchetPublicKey,
    required Uint8List ratchetPrivateKey,
  }) {
    return RatchetState(
      rootKey: Uint8List.fromList(sharedSecret),
      dhSendingPublic: Uint8List.fromList(ratchetPublicKey),
      dhSendingPrivate: Uint8List.fromList(ratchetPrivateKey),
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

    // If no sending chain key, perform DH ratchet step first.
    // M2-Crypto / Codex audit-2026-05 final-round P2: capture the old
    // dhSendingPrivate so we can zero it AFTER successful encryption.
    Uint8List? oldSendPrivToZeroOnSuccess;
    if (s.sendingChainKey == null) {
      oldSendPrivToZeroOnSuccess = state.dhSendingPrivate;
      s = await _dhRatchetSend(s);
    }

    final (newChainKey, messageKey) = await _kdfChainKey(s.sendingChainKey!);

    // Copy dhSendingPublic so the outbound header does not alias the
    // state's buffer — prevents caller mutation of either side from
    // corrupting the other.
    final header = RatchetHeader(
      dhPublicKey: Uint8List.fromList(s.dhSendingPublic),
      messageNumber: s.sendMessageNumber,
      previousChainLength: s.previousChainLength,
    );

    final ad = _concat(associatedData, header.toBytes());
    final encrypted = await _encryptWithKey(messageKey, plaintext, ad);
    // Encryption succeeded — now safe to zero the superseded key.
    if (oldSendPrivToZeroOnSuccess != null) {
      SensitiveBuffer.zeroBytes(oldSendPrivToZeroOnSuccess);
    }
    // Zero the message key — it's been used for encryption and is no longer needed.
    SensitiveBuffer.zeroBytes(messageKey);

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
    var s = _pruneExpiredSkippedKeys(state);
    final header = message.header;

    // Try skipped message keys first (out-of-order delivery)
    final skippedKey = '${base64Encode(header.dhPublicKey)}:${header.messageNumber}';
    if (s.skippedMessageKeys.containsKey(skippedKey)) {
      final mk = s.skippedMessageKeys[skippedKey]!;
      final newSkipped = Map<String, Uint8List>.from(s.skippedMessageKeys)
        ..remove(skippedKey);
      final ad = _concat(associatedData, header.toBytes());
      final plaintext = await _decryptWithKey(mk, message.ciphertext, ad);
      // Zero the consumed message key — used once, then destroyed.
      SensitiveBuffer.zeroBytes(mk);
      return (s.copyWith(skippedMessageKeys: newSkipped), plaintext);
    }

    // DH ratchet step if sender's key changed.
    // Codex audit-2026-05 R(M+L) P1: stash the old send private so we can
    // zero it AFTER successful authentication. Zeroing inside
    // _dhRatchetReceive would corrupt live state on a forged header.
    final needsDhStep = s.dhReceivingPublic == null ||
        !_bytesEqual(header.dhPublicKey, s.dhReceivingPublic!);
    Uint8List? oldSendPrivToZeroOnSuccess;

    if (needsDhStep) {
      oldSendPrivToZeroOnSuccess = s.dhSendingPrivate;
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
    // Authenticated successfully — now safe to zero the superseded send
    // private (M2-Crypto). On any throw above, this line is skipped and
    // the caller's original RatchetState remains intact.
    if (oldSendPrivToZeroOnSuccess != null) {
      SensitiveBuffer.zeroBytes(oldSendPrivToZeroOnSuccess);
    }
    // Zero the message key after decryption — single-use.
    SensitiveBuffer.zeroBytes(messageKey);
    return (s, plaintext);
  }

  // ─── DH Ratchet Steps ─────────────────────────────────────────────────────

  /// Advance the sending ratchet: generate new DH key pair, derive new chain keys.
  ///
  /// M2-Crypto (audit 2026-05): the old `dhSendingPrivate` is forward-
  /// secret material that should be zeroed once superseded. Per Codex
  /// final-round P2 we do NOT zero in-place here — `s.dhSendingPrivate`
  /// is shared by reference with the caller's state, so an in-place
  /// wipe would brick the live session if anything later in [encrypt]
  /// throws and the caller retries with the original state. Zeroing is
  /// done in [encrypt] AFTER the new state and ciphertext are produced.
  static Future<RatchetState> _dhRatchetSend(RatchetState s) async {
    final kp = await _x25519.newKeyPair();
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final priv = Uint8List.fromList(await kp.extractPrivateKeyBytes());

    final dhOut = await _dh(priv, s.dhReceivingPublic!);
    final (newRk, ck) = await _kdfRootKey(s.rootKey, dhOut);
    SensitiveBuffer.zeroBytes(dhOut);

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
  ///
  /// Codex audit-2026-05 R(M+L) P1: do NOT zero the old `dhSendingPrivate`
  /// here. This runs before message authentication; an attacker can send
  /// a forged ratchet header that triggers _dhRatchetReceive but fails
  /// MAC validation in the subsequent _decryptWithKey, and zeroing here
  /// would mutate the caller's live ratchet state in-place and brick the
  /// session. The old key is zeroed in [decrypt] AFTER decrypt succeeds.
  static Future<RatchetState> _dhRatchetReceive(
      RatchetState s, Uint8List remotePub) async {
    // Derive receiving chain key from current sending key + new remote key
    final dhOut1 = await _dh(s.dhSendingPrivate, remotePub);
    final (rk1, ckr) = await _kdfRootKey(s.rootKey, dhOut1);
    SensitiveBuffer.zeroBytes(dhOut1);

    // Generate fresh sending DH key pair for response
    final kp = await _x25519.newKeyPair();
    final newPub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final newPriv = Uint8List.fromList(await kp.extractPrivateKeyBytes());

    final dhOut2 = await _dh(newPriv, remotePub);
    final (rk2, cks) = await _kdfRootKey(rk1, dhOut2);
    SensitiveBuffer.zeroBytes(dhOut2);

    return s.copyWith(
      rootKey: rk2,
      receivingChainKey: ckr,
      sendingChainKey: cks,
      dhSendingPublic: newPub,
      dhSendingPrivate: newPriv,
      // Copy remotePub — it came from a caller-owned RatchetMessage header
      // and must not be aliased into session state.
      dhReceivingPublic: Uint8List.fromList(remotePub),
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
    final now = DateTime.now().millisecondsSinceEpoch;
    while (state.receiveMessageNumber < until) {
      final (newCk, mk) = await _kdfChainKey(state.receivingChainKey!);
      final key =
          '${base64Encode(state.dhReceivingPublic!)}:${state.receiveMessageNumber}';
      final newSkipped =
          Map<String, Uint8List>.from(state.skippedMessageKeys)..[key] = mk;
      final newTimestamps =
          Map<String, int>.from(state.skippedKeyTimestamps)..[key] = now;
      // Prune oldest entries (by timestamp) if exceeding max count
      while (newSkipped.length > _maxSkip) {
        // Find the key with the oldest timestamp, not just insertion order
        String? oldestKey;
        int oldestTime = 0x1FFFFFFFFFFFFF; // Max safe integer in JS
        for (final e in newTimestamps.entries) {
          if (e.value < oldestTime) {
            oldestTime = e.value;
            oldestKey = e.key;
          }
        }
        if (oldestKey == null) break;
        newSkipped.remove(oldestKey);
        newTimestamps.remove(oldestKey);
      }
      state = state.copyWith(
        receivingChainKey: newCk,
        receiveMessageNumber: state.receiveMessageNumber + 1,
        skippedMessageKeys: newSkipped,
        skippedKeyTimestamps: newTimestamps,
      );
    }
    return state;
  }

  /// Remove skipped message keys older than [_maxSkipAge] to preserve forward secrecy.
  static RatchetState _pruneExpiredSkippedKeys(RatchetState s) {
    if (s.skippedKeyTimestamps.isEmpty) return s;
    final cutoff = DateTime.now().millisecondsSinceEpoch -
        _maxSkipAge.inMilliseconds;
    final expired = s.skippedKeyTimestamps.entries
        .where((e) => e.value < cutoff)
        .map((e) => e.key)
        .toList();
    if (expired.isEmpty) return s;
    final newSkipped = Map<String, Uint8List>.from(s.skippedMessageKeys);
    final newTimestamps = Map<String, int>.from(s.skippedKeyTimestamps);
    for (final key in expired) {
      // Zero the key bytes before removing the reference.
      final keyBytes = newSkipped.remove(key);
      if (keyBytes != null) SensitiveBuffer.zeroBytes(keyBytes);
      newTimestamps.remove(key);
    }
    return s.copyWith(
      skippedMessageKeys: newSkipped,
      skippedKeyTimestamps: newTimestamps,
    );
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
    final newRk = Uint8List.fromList(bytes.sublist(0, 32));
    final newCk = Uint8List.fromList(bytes.sublist(32, 64));
    // Zero the 64-byte intermediate buffer — the two halves have been copied out.
    SensitiveBuffer.zeroBytes(bytes);
    return (newRk, newCk);
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
    // Validate key lengths to prevent malformed key attacks
    if (publicKey.length != 32) {
      throw StateError('Invalid DH public key length: ${publicKey.length}');
    }
    if (privateKey.length != 32) {
      throw StateError('Invalid DH private key length: ${privateKey.length}');
    }
    final kp = await _x25519.newKeyPairFromSeed(privateKey);
    final shared = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );
    final bytes = Uint8List.fromList(await shared.extractBytes());
    // Reject all-zero DH output (small-subgroup / low-order point)
    if (bytes.every((b) => b == 0)) {
      throw StateError('DH ratchet produced zero shared secret');
    }
    return bytes;
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

  /// Generate a fresh ephemeral X25519 key pair.
  static Future<(Uint8List pub, Uint8List priv)> generateEphemeralKeyPair() async {
    final kp = await _x25519.newKeyPair();
    return (
      Uint8List.fromList((await kp.extractPublicKey()).bytes),
      Uint8List.fromList(await kp.extractPrivateKeyBytes()),
    );
  }
}
