import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../../services/storage/encrypted_local_store.dart';
import '../encryption/key_pair_model.dart';
import 'prekey_bundle.dart';

/// Manages signed prekeys and one-time prekeys.
///
/// Lifecycle:
/// - Signed prekey: rotated every 7 days, old one kept for 48h overlap.
/// - One-time prekeys: pool of 100, replenished when server reports < 20.
/// - All private keys stored locally in EncryptedLocalStore.
class PreKeyManager {
  static final _x25519 = X25519();
  static final _ed25519 = Ed25519();

  static const Duration _signedPreKeyRotation = Duration(days: 7);
  static const Duration _signedPreKeyOverlap = Duration(hours: 48);

  final EncryptedLocalStore _localStore;

  SignedPreKey? _currentSignedPreKey;
  /// Previous signed prekeys kept for [_signedPreKeyOverlap] duration so that
  /// sessions initiated with the old key still complete successfully.
  final List<SignedPreKey> _previousSignedPreKeys = [];
  final List<OneTimePreKey> _oneTimePreKeys = [];
  int _nextPreKeyId = 0;

  PreKeyManager({required EncryptedLocalStore localStore})
      : _localStore = localStore;

  SignedPreKey? get currentSignedPreKey => _currentSignedPreKey;
  int get availableOneTimePreKeys => _oneTimePreKeys.length;

  /// Initialize: load existing prekeys or generate fresh ones.
  Future<void> init() async {
    await _loadFromStore();
  }

  /// Generate a signed prekey (X25519 key pair, signed with Ed25519 identity).
  ///
  /// If a current signed prekey exists, it is moved to [_previousSignedPreKeys]
  /// with a 48h overlap window so in-flight sessions using the old key complete.
  Future<SignedPreKey> generateSignedPreKey(KryptaKeyPair identityKeyPair) async {
    // Rotate current → previous (48h overlap window)
    if (_currentSignedPreKey != null) {
      _previousSignedPreKeys.add(_currentSignedPreKey!);
    }
    // Prune previous keys that have exceeded the overlap window
    _pruneExpiredPreviousKeys();

    final kp = await _x25519.newKeyPair();
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final priv = Uint8List.fromList(await kp.extractPrivateKeyBytes());

    final spk = SignedPreKey(
      id: _nextPreKeyId++,
      publicKey: pub,
      privateKey: priv,
      createdAt: DateTime.now(),
    );

    _currentSignedPreKey = spk;
    await _saveToStore();
    return spk;
  }

  /// Look up a signed prekey by ID (current or previous within overlap window).
  ///
  /// Returns null if the key is expired or not found.
  SignedPreKey? findSignedPreKey(int id) {
    if (_currentSignedPreKey?.id == id) return _currentSignedPreKey;
    _pruneExpiredPreviousKeys();
    for (final spk in _previousSignedPreKeys) {
      if (spk.id == id) return spk;
    }
    return null;
  }

  /// Remove previous signed prekeys older than the overlap window.
  void _pruneExpiredPreviousKeys() {
    final cutoff = DateTime.now().subtract(_signedPreKeyOverlap);
    _previousSignedPreKeys.removeWhere((spk) => spk.createdAt.isBefore(cutoff));
  }

  /// Sign a prekey's public key bytes using Ed25519.
  ///
  /// Returns (signature, ed25519PublicKey) so the bundle can include the
  /// signing public key for verification.
  Future<(Uint8List, Uint8List)> signPreKey(
      Uint8List preKeyPublic, Uint8List identityPrivateKey) async {
    // Derive Ed25519 signing key from X25519 identity private seed
    final signingKeyPair = await _ed25519.newKeyPairFromSeed(identityPrivateKey);
    final signingPub = await signingKeyPair.extractPublicKey();
    final signature = await _ed25519.sign(preKeyPublic, keyPair: signingKeyPair);
    return (
      Uint8List.fromList(signature.bytes),
      Uint8List.fromList(signingPub.bytes),
    );
  }

  /// Verify a signed prekey signature.
  ///
  /// Uses the Ed25519 signing public key included in the bundle (derived from
  /// the signer's identity private key). Identity binding is established via
  /// out-of-band Safety Number verification of the X25519 identity key.
  /// Verify a signed prekey signature.
  ///
  /// Requires the Ed25519 signing public key (v2 bundles). V1 bundles that
  /// lack a signing key are rejected — they must re-publish with v2.
  /// The old v1 fallback used the X25519 identity public key as Ed25519 seed,
  /// which is cryptographically broken (anyone with the public key could forge
  /// signatures). Removing it prevents MITM via forged prekey signatures.
  static Future<bool> verifyPreKeySignature({
    required Uint8List preKeyPublic,
    required Uint8List signature,
    required Uint8List identityPublicKey,
    Uint8List? signingPublicKey,
  }) async {
    try {
      if (signingPublicKey == null) {
        // v1 bundles without signing key are rejected — insecure
        return false;
      }
      final pubKey = SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519);
      final sig = Signature(signature, publicKey: pubKey);
      return await _ed25519.verify(preKeyPublic, signature: sig);
    } catch (_) {
      return false;
    }
  }

  /// Generate a batch of one-time prekeys.
  Future<List<OneTimePreKey>> generateOneTimePreKeys(int count) async {
    final keys = <OneTimePreKey>[];
    for (var i = 0; i < count; i++) {
      final kp = await _x25519.newKeyPair();
      final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
      final priv = Uint8List.fromList(await kp.extractPrivateKeyBytes());
      final opk = OneTimePreKey(id: _nextPreKeyId++, publicKey: pub, privateKey: priv);
      keys.add(opk);
      _oneTimePreKeys.add(opk);
    }
    await _saveToStore();
    return keys;
  }

  /// Consume a one-time prekey by ID (after someone used it to init a session).
  OneTimePreKey? consumeOneTimePreKey(int id) {
    final idx = _oneTimePreKeys.indexWhere((k) => k.id == id);
    if (idx == -1) return null;
    final key = _oneTimePreKeys.removeAt(idx);
    _saveToStore();
    return key;
  }

  /// Build a PreKeyBundle for publishing to Firestore.
  ///
  /// Deliberately publishes NO one-time prekey: senders would fold it into
  /// a 4-DH derivation the receive path cannot mirror (no opkId travels in
  /// the session header, and nothing consumes the matching private key),
  /// which made every first message of a new session undecryptable
  /// (Build-61 delivery bug, 2026-06). The local OTP pool stays in place
  /// for a future end-to-end implementation.
  PreKeyBundle buildBundle(
    KryptaKeyPair identityKeyPair,
    Uint8List signedPreKeySignature, {
    Uint8List? signingPublicKey,
  }) {
    return PreKeyBundle(
      identityPublicKey: identityKeyPair.publicKey,
      signedPreKeyPublic: _currentSignedPreKey!.publicKey,
      signedPreKeySignature: signedPreKeySignature,
      signedPreKeyId: _currentSignedPreKey!.id,
      signingPublicKey: signingPublicKey,
    );
  }

  /// Check if signed prekey needs rotation.
  bool needsRotation() {
    if (_currentSignedPreKey == null) return true;
    return DateTime.now().difference(_currentSignedPreKey!.createdAt) >
        _signedPreKeyRotation;
  }

  /// Check if one-time prekey pool needs replenishment.
  bool needsReplenishment() => _oneTimePreKeys.length < 20;

  /// Wipe all prekey material, zeroing private key bytes.
  Future<void> wipeAll() async {
    // Zero private key bytes before clearing references (best-effort in Dart/GC)
    if (_currentSignedPreKey != null) {
      _zeroBytes(_currentSignedPreKey!.privateKey);
    }
    for (final spk in _previousSignedPreKeys) {
      _zeroBytes(spk.privateKey);
    }
    for (final opk in _oneTimePreKeys) {
      _zeroBytes(opk.privateKey);
    }
    _currentSignedPreKey = null;
    _previousSignedPreKeys.clear();
    _oneTimePreKeys.clear();
    _nextPreKeyId = 0;
    // Store deletion handled by EncryptedLocalStore.wipeAll()
  }

  static void _zeroBytes(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  // --- Persistence ---

  Future<void> _saveToStore() async {
    final data = {
      'nextId': _nextPreKeyId,
      'spk': _currentSignedPreKey?.toMap(),
      'prevSpks': _previousSignedPreKeys.map((k) => k.toMap()).toList(),
      'opks': _oneTimePreKeys.map((k) => k.toMap()).toList(),
    };
    await _localStore.saveData('prekey_state', data);
  }

  Future<void> _loadFromStore() async {
    try {
      final data = await _localStore.loadData('prekey_state');
      if (data == null) return;
      final map = data as Map<String, dynamic>;
      _nextPreKeyId = (map['nextId'] as int?) ?? 0;
      if (map['spk'] != null) {
        _currentSignedPreKey =
            SignedPreKey.fromMap(map['spk'] as Map<String, dynamic>);
      }
      final prevSpksList = (map['prevSpks'] as List?) ?? [];
      _previousSignedPreKeys
        ..clear()
        ..addAll(prevSpksList
            .map((e) => SignedPreKey.fromMap(e as Map<String, dynamic>)));
      _pruneExpiredPreviousKeys();
      final opksList = (map['opks'] as List?) ?? [];
      _oneTimePreKeys
        ..clear()
        ..addAll(opksList
            .map((e) => OneTimePreKey.fromMap(e as Map<String, dynamic>)));
    } catch (e) {
      if (kDebugMode) debugPrint('Load prekeys failed');
    }
  }
}
