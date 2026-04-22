import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

/// A signed, hash-chained commitment to an identity public key.
///
/// Security properties:
/// - **Tamper-evident chain**: Each commitment includes the SHA-256 hash of its
///   predecessor, forming a hash chain. The server cannot insert, remove, or
///   reorder entries without breaking the chain.
/// - **Self-signed**: Ed25519 signature proves the commitment was created by
///   the key owner, not forged by the server.
/// - **Monotonic epochs**: Strictly increasing epoch numbers detect gaps and
///   prevent replay of stale commitments.
/// - **Binding**: The commitment hash binds epoch + key + chain + timestamp
///   together — changing any field invalidates the signature.
class KeyCommitment {
  /// Monotonic epoch counter — strictly increases with each commitment.
  final int epoch;

  /// The identity public key being committed (32 bytes, X25519).
  final Uint8List identityPublicKey;

  /// SHA-256 hash of the previous commitment's canonical bytes.
  /// All-zero for the genesis commitment (epoch 0).
  final Uint8List previousCommitHash;

  /// When this commitment was created (milliseconds since epoch).
  final int timestampMs;

  /// Ed25519 signature over the commitment's canonical bytes.
  final Uint8List signature;

  /// Ed25519 public key used for signature verification.
  /// Derived from the identity private key — binding to the identity key
  /// is established via out-of-band Safety Number verification.
  final Uint8List signingPublicKey;

  /// Algorithm version for future-proofing. Must be 1 for current impl.
  static const int currentVersion = 1;

  static final _ed25519 = Ed25519();

  KeyCommitment({
    required this.epoch,
    required this.identityPublicKey,
    required this.previousCommitHash,
    required this.timestampMs,
    required this.signature,
    required this.signingPublicKey,
  });

  /// Genesis hash: 32 zero bytes. Used as previousCommitHash for epoch 0.
  /// Returns a fresh copy each call to prevent external mutation.
  static Uint8List get genesisHash => Uint8List(32);

  /// Canonical byte representation for hashing and signing.
  ///
  /// Format: version(1) || epoch(8 BE) || identityPublicKey(32) ||
  ///         previousCommitHash(32) || timestampMs(8 BE)
  /// Total: 81 bytes (fixed-length, no ambiguity).
  Uint8List get canonicalBytes {
    final buf = Uint8List(1 + 8 + 32 + 32 + 8);
    buf[0] = currentVersion;
    _writeInt64BE(buf, 1, epoch);
    buf.setRange(9, 41, identityPublicKey);
    buf.setRange(41, 73, previousCommitHash);
    _writeInt64BE(buf, 73, timestampMs);
    return buf;
  }

  /// Cached commit hash (SHA-256 of canonical bytes).
  Uint8List? _cachedCommitHash;

  /// SHA-256 hash of the canonical bytes — used as chain link and audit ID.
  /// Cached after first computation since all fields are final.
  Uint8List get commitHash {
    if (_cachedCommitHash != null) return _cachedCommitHash!;
    final digest = crypto.sha256.convert(canonicalBytes);
    _cachedCommitHash = Uint8List.fromList(digest.bytes);
    return _cachedCommitHash!;
  }

  /// Create and sign a new commitment.
  ///
  /// [identityPrivateKey] is the X25519 private key used as Ed25519 seed.
  /// [previousHash] is the commitHash of the previous commitment (or
  /// [genesisHash] for the first commitment).
  static Future<KeyCommitment> create({
    required int epoch,
    required Uint8List identityPublicKey,
    required Uint8List identityPrivateKey,
    required Uint8List previousHash,
  }) async {
    final timestampMs = DateTime.now().millisecondsSinceEpoch;

    // Derive Ed25519 signing key from X25519 identity private seed
    final signingKeyPair = await _ed25519.newKeyPairFromSeed(identityPrivateKey);
    final signingPub = Uint8List.fromList(
        (await signingKeyPair.extractPublicKey()).bytes);

    // Build canonical bytes for signing
    final commitment = KeyCommitment(
      epoch: epoch,
      identityPublicKey: identityPublicKey,
      previousCommitHash: previousHash,
      timestampMs: timestampMs,
      signature: Uint8List(0), // placeholder
      signingPublicKey: signingPub,
    );

    final sig = await _ed25519.sign(
      commitment.canonicalBytes,
      keyPair: signingKeyPair,
    );

    return KeyCommitment(
      epoch: epoch,
      identityPublicKey: identityPublicKey,
      previousCommitHash: previousHash,
      timestampMs: timestampMs,
      signature: Uint8List.fromList(sig.bytes),
      signingPublicKey: signingPub,
    );
  }

  /// Verify the Ed25519 signature on this commitment.
  ///
  /// Returns false if the signature is invalid or malformed.
  /// Fail-closed: any exception → false.
  Future<bool> verifySignature() async {
    try {
      final pubKey = SimplePublicKey(
        signingPublicKey,
        type: KeyPairType.ed25519,
      );
      final sig = Signature(signature, publicKey: pubKey);
      return await _ed25519.verify(canonicalBytes, signature: sig);
    } catch (_) {
      return false;
    }
  }

  /// Verify that this commitment correctly chains to a given previous hash.
  bool verifiesAgainst(Uint8List expectedPreviousHash) {
    if (previousCommitHash.length != expectedPreviousHash.length) return false;
    var diff = 0;
    for (var i = 0; i < previousCommitHash.length; i++) {
      diff |= previousCommitHash[i] ^ expectedPreviousHash[i];
    }
    return diff == 0;
  }

  /// Whether this is the genesis (first) commitment.
  bool get isGenesis => epoch == 0 && _isAllZero(previousCommitHash);

  static bool _isAllZero(Uint8List bytes) {
    for (final b in bytes) {
      if (b != 0) return false;
    }
    return true;
  }

  Map<String, dynamic> toMap() => {
        'e': epoch,
        'k': base64Encode(identityPublicKey),
        'p': base64Encode(previousCommitHash),
        'ts': timestampMs,
        's': base64Encode(signature),
        'sp': base64Encode(signingPublicKey),
      };

  factory KeyCommitment.fromMap(Map<String, dynamic> map) {
    return KeyCommitment(
      epoch: map['e'] as int,
      identityPublicKey: base64Decode(map['k'] as String),
      previousCommitHash: base64Decode(map['p'] as String),
      timestampMs: map['ts'] as int,
      signature: base64Decode(map['s'] as String),
      signingPublicKey: base64Decode(map['sp'] as String),
    );
  }

  static void _writeInt64BE(Uint8List buf, int offset, int value) {
    for (var i = 7; i >= 0; i--) {
      buf[offset + i] = value & 0xFF;
      value >>= 8;
    }
  }
}
