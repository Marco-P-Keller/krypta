import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/storage_keys.dart';

/// Wrapper around FlutterSecureStorage for app-level secrets.
/// Handles code storage, setup state, and user preferences.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  // --- Setup State ---

  Future<bool> isSetupComplete() async {
    final value = await _storage.read(key: StorageKeys.setupComplete);
    return value == 'true';
  }

  Future<void> markSetupComplete() async {
    await _storage.write(key: StorageKeys.setupComplete, value: 'true');
  }

  // --- Code Management ---

  Future<void> saveSecretCode(String code) async {
    await _storage.write(key: StorageKeys.secretCode, value: code);
  }

  Future<void> saveDecoyCode(String code) async {
    await _storage.write(key: StorageKeys.decoyCode, value: code);
  }

  Future<void> saveDeleteCode(String code) async {
    await _storage.write(key: StorageKeys.deleteCode, value: code);
  }

  Future<String?> getSecretCode() async {
    return _storage.read(key: StorageKeys.secretCode);
  }

  Future<String?> getDecoyCode() async {
    return _storage.read(key: StorageKeys.decoyCode);
  }

  Future<String?> getDeleteCode() async {
    return _storage.read(key: StorageKeys.deleteCode);
  }

  // --- User ID ---

  Future<void> saveUserId(String uid) async {
    await _storage.write(key: StorageKeys.userId, value: uid);
  }

  Future<String?> getUserId() async {
    return _storage.read(key: StorageKeys.userId);
  }

  // --- Preferences ---

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
      key: StorageKeys.biometricEnabled,
      value: enabled.toString(),
    );
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: StorageKeys.biometricEnabled);
    return value == 'true';
  }

  // --- Vault Password ---

  Future<void> setVaultPassword(String password) async {
    await _storage.write(key: StorageKeys.vaultPassword, value: password);
    await _storage.write(key: StorageKeys.vaultPasswordEnabled, value: 'true');
  }

  Future<void> removeVaultPassword() async {
    await _storage.delete(key: StorageKeys.vaultPassword);
    await _storage.write(key: StorageKeys.vaultPasswordEnabled, value: 'false');
  }

  Future<bool> isVaultPasswordEnabled() async {
    final value = await _storage.read(key: StorageKeys.vaultPasswordEnabled);
    return value == 'true';
  }

  Future<bool> verifyVaultPassword(String input) async {
    final stored = await _storage.read(key: StorageKeys.vaultPassword);
    return stored != null && stored == input;
  }

  // --- Wipe ---

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
