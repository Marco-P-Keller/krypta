import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/storage_keys.dart';
import '../encryption/encryption_service.dart';
import '../encryption/key_pair_model.dart';

/// Manages identity key pairs.
/// Keys are generated once and stored securely in platform keychain/keystore.
/// Keys never leave the device unencrypted.
class KeyManager {
  final FlutterSecureStorage _storage;
  final EncryptionService _encryption;

  KryptaKeyPair? _cachedIdentityKeyPair;

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

  Future<KryptaKeyPair> getOrCreateIdentityKeyPair() async {
    if (_cachedIdentityKeyPair != null) return _cachedIdentityKeyPair!;

    final existingPriv = await _storage.read(key: StorageKeys.identityPrivateKey);
    final existingPub = await _storage.read(key: StorageKeys.identityPublicKey);

    if (existingPriv != null && existingPub != null) {
      _cachedIdentityKeyPair = KryptaKeyPair.fromBase64(
        privateKeyBase64: existingPriv,
        publicKeyBase64: existingPub,
      );
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

    _cachedIdentityKeyPair = keyPair;
    return keyPair;
  }

  Future<void> deleteAllKeys() async {
    _cachedIdentityKeyPair = null;
    await _storage.delete(key: StorageKeys.identityPrivateKey);
    await _storage.delete(key: StorageKeys.identityPublicKey);
    await _storage.delete(key: StorageKeys.preKeyPrivate);
    await _storage.delete(key: StorageKeys.preKeyPublic);
    await _storage.delete(key: StorageKeys.databaseKey);
  }

  bool get hasKeysInMemory => _cachedIdentityKeyPair != null;

  void clearMemoryCache() {
    _cachedIdentityKeyPair = null;
  }
}
