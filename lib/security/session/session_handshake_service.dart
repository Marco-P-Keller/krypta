import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../encryption/key_pair_model.dart';
import '../prekey/prekey_bundle.dart';
import '../prekey/prekey_manager.dart';
import '../ratchet/double_ratchet.dart';
import '../ratchet/ratchet_state.dart';

/// Dedicated session handshake service implementing X3DH key agreement.
///
/// Separates the critical handshake logic from MessengerProvider.
///
/// Security guarantees:
/// - No message without a valid session
/// - No session without signature verification
/// - No silent fallback logic
///
/// Protocol:
/// 1. Sender fetches recipient's PreKeyBundle
/// 2. Sender verifies signed prekey signature (Ed25519)
/// 3. Sender performs 3-DH (or 4-DH with one-time prekey)
/// 4. Shared secret → Double Ratchet initialization
class SessionHandshakeService {
  static final _x25519 = X25519();

  /// Create an outbound session (we are initiating contact).
  ///
  /// Performs X3DH key agreement with the recipient's PreKeyBundle:
  /// - DH1 = DH(identity_priv, signed_prekey_pub)
  /// - DH2 = DH(ephemeral_priv, identity_pub)
  /// - DH3 = DH(ephemeral_priv, signed_prekey_pub)
  ///
  /// Always 3-DH. A bundle's one-time prekey is deliberately IGNORED:
  /// the session header only transmits our ephemeral key (no opkId), and
  /// no receiver-side OTP lookup/consumption exists — a 4-DH secret would
  /// be underivable for the receiver and every first message of the
  /// session would fail its MAC check (Build-61 delivery bug, 2026-06).
  /// Full OTP support needs opkId on the wire plus receiver consumption,
  /// on BOTH sides, before DH4 may come back.
  ///
  /// Throws [HandshakeException] if signature verification fails.
  static Future<OutboundSession> createOutboundSession({
    required KryptaKeyPair identityKeyPair,
    required PreKeyBundle bundle,
  }) async {
    // Step 1: Verify signed prekey signature — MANDATORY
    final signatureValid = await verifySignedPreKey(
      preKeyPublic: bundle.signedPreKeyPublic,
      signature: bundle.signedPreKeySignature,
      identityPublicKey: bundle.identityPublicKey,
      signingPublicKey: bundle.signingPublicKey,
    );

    if (!signatureValid) {
      throw HandshakeException(
        'Signed prekey signature verification failed. '
        'Possible MITM attack — aborting session.',
      );
    }

    // Step 2: Generate ephemeral key pair
    final ephKeyPair = await _x25519.newKeyPair();
    final ephPublic = Uint8List.fromList(
        (await ephKeyPair.extractPublicKey()).bytes);
    final ephPrivate = Uint8List.fromList(
        await ephKeyPair.extractPrivateKeyBytes());

    // L2-Crypto (audit 2026-05): wrap DH key material in try/finally so
    // an exception between the DH calls and the explicit zeroing doesn't
    // leave secret bytes lingering in memory.
    Uint8List? dh1, dh2, dh3, ikm, sharedSecret;
    try {
      // Step 3: Perform X3DH key agreement (3-DH — see class comment on
      // why the bundle's one-time prekey must not enter the derivation)
      // DH1: identity_priv × signed_prekey_pub
      dh1 = await _dh(identityKeyPair.privateKey, bundle.signedPreKeyPublic);
      // DH2: ephemeral_priv × identity_pub
      dh2 = await _dh(ephPrivate, bundle.identityPublicKey);
      // DH3: ephemeral_priv × signed_prekey_pub
      dh3 = await _dh(ephPrivate, bundle.signedPreKeyPublic);

      ikm = _concat3(dh1, dh2, dh3);

      // Step 4: Derive shared secret via HKDF
      sharedSecret = await _deriveSharedSecret(ikm);

      // Step 5: Initialize Double Ratchet as sender
      final ratchetState = await DoubleRatchet.initAsSender(
        sharedSecret: sharedSecret,
        recipientRatchetPublicKey: bundle.signedPreKeyPublic,
      );

      return OutboundSession(
        ratchetState: ratchetState,
        ephemeralPublicKey: ephPublic,
        signedPreKeyId: bundle.signedPreKeyId,
      );
    } finally {
      // Zero in finally so even an early throw cleans up. Order doesn't
      // matter; each is independent.
      _zeroBytes(ephPrivate);
      if (dh1 != null) _zeroBytes(dh1);
      if (dh2 != null) _zeroBytes(dh2);
      if (dh3 != null) _zeroBytes(dh3);
      if (ikm != null) _zeroBytes(ikm);
      if (sharedSecret != null) _zeroBytes(sharedSecret);
    }
  }

  /// Create an inbound session (we are receiving a first message).
  ///
  /// Performs the receiver side of X3DH (3-DH, mirroring
  /// [createOutboundSession] / [deriveFallbackSecret]):
  /// - DH1 = DH(signed_prekey_priv, sender_identity_pub)
  /// - DH2 = DH(identity_priv, sender_ephemeral_pub)
  /// - DH3 = DH(signed_prekey_priv, sender_ephemeral_pub)
  ///         OR DH(identity_priv, sender_ephemeral2_pub) in fallback path
  ///
  /// The receiver's initial ratchet key pair MUST be the signed prekey
  /// (matching what the sender used as recipientRatchetPublicKey).
  /// Pass the signed prekey via [signedPreKeyPublic]/[signedPreKeyPrivate].
  /// In the fallback (message carries ek2), these MUST be the identity
  /// key pair — use [resolveInboundHandshakeKeys] to pick correctly.
  ///
  /// [senderEphemeral2Public]: If present (fallback path), DH3 uses this
  /// separate ephemeral key to ensure 3 independent DH outputs.
  static Future<RatchetState> createInboundSession({
    required KryptaKeyPair identityKeyPair,
    required Uint8List signedPreKeyPrivate,
    required Uint8List signedPreKeyPublic,
    required Uint8List senderIdentityPublic,
    required Uint8List senderEphemeralPublic,
    Uint8List? senderEphemeral2Public,
  }) async {
    // L2-Crypto: try/finally with explicit zeroing.
    Uint8List? dh1, dh2, dh3, ikm, sharedSecret;
    try {
      // DH1: signed_prekey_priv × sender_identity_pub
      dh1 = await _dh(signedPreKeyPrivate, senderIdentityPublic);
      // DH2: identity_priv × sender_ephemeral_pub
      dh2 = await _dh(identityKeyPair.privateKey, senderEphemeralPublic);
      // DH3: In fallback path with ek2, use the second ephemeral key for independence.
      //       In normal X3DH, use signed_prekey_priv × sender_ephemeral_pub.
      if (senderEphemeral2Public != null) {
        dh3 = await _dh(identityKeyPair.privateKey, senderEphemeral2Public);
      } else {
        dh3 = await _dh(signedPreKeyPrivate, senderEphemeralPublic);
      }

      ikm = _concat3(dh1, dh2, dh3);

      sharedSecret = await _deriveSharedSecret(ikm);

      // The ratchet key pair must match what the sender used as
      // recipientRatchetPublicKey — which is the signed prekey.
      return DoubleRatchet.initAsReceiver(
        sharedSecret: sharedSecret,
        ratchetPublicKey: signedPreKeyPublic,
        ratchetPrivateKey: signedPreKeyPrivate,
      );
    } finally {
      if (dh1 != null) _zeroBytes(dh1);
      if (dh2 != null) _zeroBytes(dh2);
      if (dh3 != null) _zeroBytes(dh3);
      if (ikm != null) _zeroBytes(ikm);
      if (sharedSecret != null) _zeroBytes(sharedSecret);
    }
  }

  /// Select which local key pair mirrors an inbound X3DH handshake.
  ///
  /// The sender's derivation dictates the answer (Build-61 delivery bug:
  /// picking the wrong pair makes every first message undecryptable):
  /// - Fallback handshake (message carries `ek2`): the sender derived all
  ///   DH outputs against our IDENTITY key and initialized its ratchet
  ///   against it → mirror with the identity pair. Never the signed prekey.
  /// - Bundle handshake: the sender used the signed prekey from our
  ///   published bundle. Resolve it by the transmitted [signedPreKeyId]
  ///   (covers rotation: the matching key may be a previous one still
  ///   inside the 48h overlap window). Without an id or a match, use the
  ///   current signed prekey; without any prekeys, the identity pair.
  ///
  /// Returns (privateKey, publicKey).
  static (Uint8List, Uint8List) resolveInboundHandshakeKeys({
    required bool isFallback,
    required int? signedPreKeyId,
    required KryptaKeyPair identityKeyPair,
    required SignedPreKey? currentSignedPreKey,
    required SignedPreKey? Function(int id) findSignedPreKeyById,
  }) {
    if (isFallback) {
      return (identityKeyPair.privateKey, identityKeyPair.publicKey);
    }
    if (signedPreKeyId != null) {
      final match = findSignedPreKeyById(signedPreKeyId);
      if (match != null) {
        return (match.privateKey, match.publicKey);
      }
    }
    if (currentSignedPreKey != null) {
      return (currentSignedPreKey.privateKey, currentSignedPreKey.publicKey);
    }
    return (identityKeyPair.privateKey, identityKeyPair.publicKey);
  }

  /// Verify a signed prekey's Ed25519 signature.
  ///
  /// This MUST succeed before any session is created.
  /// A failed verification means the key may have been tampered with.
  static Future<bool> verifySignedPreKey({
    required Uint8List preKeyPublic,
    required Uint8List signature,
    required Uint8List identityPublicKey,
    Uint8List? signingPublicKey,
  }) async {
    return PreKeyManager.verifyPreKeySignature(
      preKeyPublic: preKeyPublic,
      signature: signature,
      identityPublicKey: identityPublicKey,
      signingPublicKey: signingPublicKey,
    );
  }

  /// Fallback shared secret derivation when no PreKeyBundle is available.
  ///
  /// Uses 3-DH with a separate ephemeral key for DH3 to ensure 3 independent
  /// DH outputs (previously DH3 = DH2 which weakened the key agreement):
  ///   DH1 = DH(identity_priv, recipient_identity_pub)
  ///   DH2 = DH(ephemeral_priv, recipient_identity_pub)
  ///   DH3 = DH(ephemeral2_priv, recipient_identity_pub)  [independent]
  ///   concat(DH1, DH2, DH3) → HKDF("KryptaX3DH-v1") → 32 bytes
  ///
  /// Returns (sharedSecret, ephemeral2PublicKey) — the second ephemeral
  /// public key must be transmitted so the receiver can compute DH3.
  static Future<(Uint8List, Uint8List)> deriveFallbackSecret({
    required Uint8List identityPrivate,
    required Uint8List ephemeralPrivate,
    required Uint8List recipientIdentityPublic,
  }) async {
    // L2-Crypto: try/finally for crash-safe zeroing.
    Uint8List? dh1, dh2, dh3, ikm, eph2Private;
    try {
      dh1 = await _dh(identityPrivate, recipientIdentityPublic);
      dh2 = await _dh(ephemeralPrivate, recipientIdentityPublic);

      // Generate a second ephemeral key pair for DH3 — ensures 3 independent DH outputs
      final eph2KeyPair = await _x25519.newKeyPair();
      final eph2Public = Uint8List.fromList(
          (await eph2KeyPair.extractPublicKey()).bytes);
      eph2Private = Uint8List.fromList(
          await eph2KeyPair.extractPrivateKeyBytes());

      dh3 = await _dh(eph2Private, recipientIdentityPublic);
      ikm = _concat3(dh1, dh2, dh3);
      final secret = await _deriveSharedSecret(ikm);

      return (secret, eph2Public);
    } finally {
      if (dh1 != null) _zeroBytes(dh1);
      if (dh2 != null) _zeroBytes(dh2);
      if (dh3 != null) _zeroBytes(dh3);
      if (eph2Private != null) _zeroBytes(eph2Private);
      if (ikm != null) _zeroBytes(ikm);
    }
  }

  // ─── Crypto Helpers ─────────────────────────────────────────────────────────

  static Future<Uint8List> _dh(
      Uint8List privateKey, Uint8List publicKey) async {
    // Validate key lengths to prevent malformed key attacks
    if (publicKey.length != 32) {
      throw HandshakeException(
          'Invalid DH public key length: ${publicKey.length}');
    }
    if (privateKey.length != 32) {
      throw HandshakeException(
          'Invalid DH private key length: ${privateKey.length}');
    }
    final kp = await _x25519.newKeyPairFromSeed(privateKey);
    final shared = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );
    final bytes = Uint8List.fromList(await shared.extractBytes());

    // Reject all-zero shared secret (low-order point attack).
    // X25519 can produce zero output if the remote public key is a
    // small-subgroup element — this would give no secrecy.
    if (bytes.every((b) => b == 0)) {
      throw HandshakeException('DH produced zero shared secret — rejected');
    }
    return bytes;
  }

  static Future<Uint8List> _deriveSharedSecret(Uint8List ikm) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: Uint8List(32), // zero salt per X3DH spec
      info: utf8.encode('KryptaX3DH-v1'),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  static Uint8List _concat3(Uint8List a, Uint8List b, Uint8List c) {
    final r = Uint8List(a.length + b.length + c.length);
    r.setRange(0, a.length, a);
    r.setRange(a.length, a.length + b.length, b);
    r.setRange(a.length + b.length, r.length, c);
    return r;
  }

  /// Best-effort zero of byte array (Dart GC may retain copies).
  static void _zeroBytes(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}

/// Result of an outbound X3DH handshake.
class OutboundSession {
  final RatchetState ratchetState;
  final Uint8List ephemeralPublicKey;

  /// Id of the bundle's signed prekey used in the derivation. Travels in
  /// the session header (`spkId`) so the receiver can resolve the same
  /// key even after a rotation.
  final int signedPreKeyId;

  const OutboundSession({
    required this.ratchetState,
    required this.ephemeralPublicKey,
    required this.signedPreKeyId,
  });
}

/// Thrown when a handshake fails security checks.
class HandshakeException implements Exception {
  final String message;
  const HandshakeException(this.message);
  @override
  String toString() => 'HandshakeException: $message';
}
