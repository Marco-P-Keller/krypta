import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/storage_keys.dart';
import '../encryption/encryption_service.dart';
import '../encryption/key_pair_model.dart';
import '../transparency/key_commitment.dart';
import '../transparency/key_transparency_log.dart';

/// Manages identity key pairs with memory hygiene.
///
/// Security model:
/// - Keys are generated once and stored in platform keychain/keystore
/// - Keys never leave the device unencrypted
/// - In-memory cache is limited and cleared after use
/// - Private key bytes are zeroed on cache clear
/// - Key creation publishes a signed commitment to the transparency log
class KeyManager {
  final FlutterSecureStorage _storage;
  final EncryptionService _encryption;

  /// Transparency log for publishing self-commitments.
  KeyTransparencyLog? _transparencyLog;

  /// Callback to publish commitment to the server.
  Future<void> Function(KeyCommitment commitment)? _onCommitmentCreated;

  KryptaKeyPair? _cachedIdentityKeyPair;

  /// Track when cache was last accessed to enable automatic clearing.
  DateTime? _cacheAccessTime;

  /// Auto-clear cache after this duration of inactivity.
  /// 3 minutes balances performance (avoid re-reads from keychain)
  /// with minimizing RAM exposure of private key material.
  static const _cacheTimeout = Duration(minutes: 3);

  KeyManager({
    FlutterSecureStorage? storage,
    EncryptionService? encryption,
  })          : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        ),
        _encryption = encryption ?? EncryptionService();

  /// Attach Key Transparency log and publish callback.
  ///
  /// Must be called after construction to enable commitment publishing.
  /// Without this, key creation works but no transparency commitments
  /// are published (graceful degradation for tests and migration).
  void setTransparency({
    required KeyTransparencyLog log,
    required Future<void> Function(KeyCommitment commitment) onCommitmentCreated,
  }) {
    _transparencyLog = log;
    _onCommitmentCreated = onCommitmentCreated;
  }

  Future<KryptaKeyPair> getOrCreateIdentityKeyPair() async {
    // Check cache timeout
    if (_cachedIdentityKeyPair != null && _cacheAccessTime != null) {
      if (DateTime.now().difference(_cacheAccessTime!) > _cacheTimeout) {
        clearMemoryCache();
      }
    }

    if (_cachedIdentityKeyPair != null) {
      _cacheAccessTime = DateTime.now();
      return _cachedIdentityKeyPair!;
    }

    final existingPriv = await _storage.read(key: StorageKeys.identityPrivateKey);
    final existingPub = await _storage.read(key: StorageKeys.identityPublicKey);

    if (existingPriv != null && existingPub != null) {
      _cachedIdentityKeyPair = KryptaKeyPair.fromBase64(
        privateKeyBase64: existingPriv,
        publicKeyBase64: existingPub,
      );
      _cacheAccessTime = DateTime.now();

      // Retry genesis commitment if it failed earlier (e.g., userId wasn't available)
      if (!_genesisCommitmentPublished && _transparencyLog != null) {
        await _publishKeyCommitment(_cachedIdentityKeyPair!);
      }

      return _cachedIdentityKeyPair!;
    }

    final keyPair = await _encryption.generateIdentityKeyPair();
    await _storage.write(
      key: StorageKeys.identityPrivateKey,
      value: keyPair.privateKeyBase64,
    );
    await _storage.write(
      key: StorageKeys.identityPublicKey,
      value: keyPair.publicKeyBase64,
    );

    // Publish genesis commitment to Key Transparency log
    await _publishKeyCommitment(keyPair);

    _cachedIdentityKeyPair = keyPair;
    _cacheAccessTime = DateTime.now();
    return keyPair;
  }

  Future<void> deleteAllKeys() async {
    clearMemoryCache();
    await _storage.delete(key: StorageKeys.identityPrivateKey);
    await _storage.delete(key: StorageKeys.identityPublicKey);
    await _storage.delete(key: StorageKeys.preKeyPrivate);
    await _storage.delete(key: StorageKeys.preKeyPublic);
    await _storage.delete(key: StorageKeys.databaseKey);
    await _storage.delete(key: StorageKeys.databaseKeyWrapped);
  }

  /// Returns true when identity key material is currently persisted.
  /// Used to verify the post-wipe state (H3): if this returns true after
  /// `deleteAllKeys()` the wipe was interrupted and the marker must persist.
  Future<bool> hasIdentityKeys() async {
    final priv = await _storage.read(key: StorageKeys.identityPrivateKey);
    final pub = await _storage.read(key: StorageKeys.identityPublicKey);
    return priv != null || pub != null;
  }

  bool get hasKeysInMemory => _cachedIdentityKeyPair != null;

  /// Whether the genesis commitment has been published for the current key.
  /// If false, [_publishKeyCommitment] will retry on next key access.
  bool _genesisCommitmentPublished = false;

  /// Create and publish a signed key commitment.
  ///
  /// Fails silently if transparency is not configured (graceful degradation).
  /// The commitment is both stored locally and published via callback.
  /// If userId is not yet available (first setup), sets a flag to retry
  /// on next key access rather than silently dropping the genesis commitment.
  Future<void> _publishKeyCommitment(KryptaKeyPair keyPair) async {
    if (_transparencyLog == null || _onCommitmentCreated == null) return;

    try {
      // Read userId to determine the storage key for our own log
      final userId = await _storage.read(key: StorageKeys.userId);
      if (userId == null) {
        // userId not yet available (first setup before auth).
        // Mark as unpublished so we retry on next getOrCreateIdentityKeyPair().
        _genesisCommitmentPublished = false;
        return;
      }

      final currentEpoch = await _transparencyLog!.getLatestEpoch(userId);
      final previousHash = await _transparencyLog!.getHeadHash(userId);

      final commitment = await KeyCommitment.create(
        epoch: currentEpoch + 1,
        identityPublicKey: keyPair.publicKey,
        identityPrivateKey: keyPair.privateKey,
        previousHash: previousHash,
      );

      // Store locally first (fail-closed: if local storage fails, don't publish)
      final result = await _transparencyLog!.verifyAndAppend(
        userId: userId,
        commitment: commitment,
        expectedPublicKey: keyPair.publicKey,
      );

      if (result == CommitmentVerifyResult.valid) {
        await _onCommitmentCreated!(commitment);
        _genesisCommitmentPublished = true;
      }
    } catch (_) {
      // Best-effort: transparency failure must not block key creation
    }
  }

  /// Zero out cached key bytes and clear reference.
  ///
  /// Best-effort: Dart doesn't guarantee memory zeroing due to GC,
  /// but this prevents casual inspection and reduces the window
  /// where keys are in memory.
  void clearMemoryCache() {
    if (_cachedIdentityKeyPair != null) {
      _zeroBytes(_cachedIdentityKeyPair!.privateKey);
      _cachedIdentityKeyPair = null;
    }
    _cacheAccessTime = null;
  }

  /// Best-effort zero of byte array.
  static void _zeroBytes(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}
