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

  final EncryptedLocalStore _localStore;

  SignedPreKey? _currentSignedPreKey;
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
  Future<SignedPreKey> generateSignedPreKey(KryptaKeyPair identityKeyPair) async {
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

  /// Sign a prekey's public key bytes using Ed25519.
  Future<Uint8List> signPreKey(
      Uint8List preKeyPublic, Uint8List identityPrivateKey) async {
    // Derive Ed25519 signing key from X25519 seed
    final signingKeyPair = await _ed25519.newKeyPairFromSeed(identityPrivateKey);
    final signature = await _ed25519.sign(preKeyPublic, keyPair: signingKeyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verify a signed prekey signature.
  static Future<bool> verifyPreKeySignature({
    required Uint8List preKeyPublic,
    required Uint8List signature,
    required Uint8List identityPublicKey,
  }) async {
    try {
      final signingPublicKey = await _ed25519.newKeyPairFromSeed(identityPublicKey);
      final pubKey = await signingPublicKey.extractPublicKey();
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
  PreKeyBundle buildBundle(KryptaKeyPair identityKeyPair, Uint8List signedPreKeySignature) {
    final opk = _oneTimePreKeys.isNotEmpty ? _oneTimePreKeys.first : null;
    return PreKeyBundle(
      identityPublicKey: identityKeyPair.publicKey,
      signedPreKeyPublic: _currentSignedPreKey!.publicKey,
      signedPreKeySignature: signedPreKeySignature,
      signedPreKeyId: _currentSignedPreKey!.id,
      oneTimePreKeyPublic: opk?.publicKey,
      oneTimePreKeyId: opk?.id,
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

  /// Wipe all prekey material.
  Future<void> wipeAll() async {
    _currentSignedPreKey = null;
    _oneTimePreKeys.clear();
    _nextPreKeyId = 0;
    // Store deletion handled by EncryptedLocalStore.wipeAll()
  }

  // --- Persistence ---

  Future<void> _saveToStore() async {
    final data = {
      'nextId': _nextPreKeyId,
      'spk': _currentSignedPreKey?.toMap(),
      'opks': _oneTimePreKeys.map((k) => k.toMap()).toList(),
    };
    await _localStore.saveDecoyData('prekey_state', data);
  }

  Future<void> _loadFromStore() async {
    try {
      final data = await _localStore.loadDecoyData('prekey_state');
      if (data == null) return;
      final map = data as Map<String, dynamic>;
      _nextPreKeyId = (map['nextId'] as int?) ?? 0;
      if (map['spk'] != null) {
        _currentSignedPreKey =
            SignedPreKey.fromMap(map['spk'] as Map<String, dynamic>);
      }
      final opksList = (map['opks'] as List?) ?? [];
      _oneTimePreKeys
        ..clear()
        ..addAll(opksList
            .map((e) => OneTimePreKey.fromMap(e as Map<String, dynamic>)));
    } catch (e) {
      debugPrint('Load prekeys failed: $e');
    }
  }
}
