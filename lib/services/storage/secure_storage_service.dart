import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/storage_keys.dart';

/// Wrapper around FlutterSecureStorage for app-level secrets.
///
/// Security model:
/// - Vault password: stored as Argon2id(password, salt) — never plaintext
/// - Codes: stored as Argon2id(code, salt) — never plaintext
/// - Setup state, preferences: stored as plain flags (no secret value)
/// - User ID: not a secret, stored plain
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  // --- Argon2id helpers ---

  static final _argon2 = Argon2id(
    parallelism: 1,
    memory: 19456, // 19 MiB — OWASP minimum for interactive
    iterations: 2,
    hashLength: 32,
  );

  static Uint8List _randomSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  }

  /// Returns "$base64salt:$base64hash"
  static Future<String> _hashSecret(String secret) async {
    final salt = _randomSalt();
    final hash = await _argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
    );
    final hashBytes = await hash.extractBytes();
    return '${base64Encode(salt)}:${base64Encode(hashBytes)}';
  }

  /// Constant-time comparison of Argon2id hash against candidate.
  static Future<bool> _verifySecret(String candidate, String stored) async {
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final salt = base64Decode(parts[0]);
    final expectedHash = base64Decode(parts[1]);
    final hash = await _argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(candidate)),
      nonce: salt,
    );
    final hashBytes = await hash.extractBytes();
    // Constant-time compare
    if (hashBytes.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < hashBytes.length; i++) {
      diff |= hashBytes[i] ^ expectedHash[i];
    }
    return diff == 0;
  }

  // --- Setup State ---

  Future<bool> isSetupComplete() async {
    final value = await _storage.read(key: StorageKeys.setupComplete);
    return value == 'true';
  }

  Future<void> markSetupComplete() async {
    await _storage.write(key: StorageKeys.setupComplete, value: 'true');
  }

  // --- Code Management (hashed) ---

  Future<void> saveSecretCode(String code) async {
    await _storage.write(key: StorageKeys.secretCode, value: await _hashSecret(code));
  }

  Future<void> saveDecoyCode(String code) async {
    await _storage.write(key: StorageKeys.decoyCode, value: await _hashSecret(code));
  }

  Future<void> saveDeleteCode(String code) async {
    await _storage.write(key: StorageKeys.deleteCode, value: await _hashSecret(code));
  }

  Future<bool> verifySecretCode(String code) async {
    final stored = await _storage.read(key: StorageKeys.secretCode);
    if (stored == null) return false;
    return _verifySecret(code, stored);
  }

  Future<bool> verifyDecoyCode(String code) async {
    final stored = await _storage.read(key: StorageKeys.decoyCode);
    if (stored == null) return false;
    return _verifySecret(code, stored);
  }

  Future<bool> verifyDeleteCode(String code) async {
    final stored = await _storage.read(key: StorageKeys.deleteCode);
    if (stored == null) return false;
    return _verifySecret(code, stored);
  }

  /// Check if a proposed code collides with any existing stored codes.
  ///
  /// Returns true if the candidate exactly matches an existing code.
  /// Prevents identical codes (e.g., secret == decoy would always trigger the
  /// wrong action). Note: prefix detection (e.g., "1234" vs "12345") is not
  /// possible with Argon2id hashing — the CodeDetector must enforce minimum
  /// code lengths to mitigate prefix overlap risk.
  Future<bool> codeCollides(String candidate, {String? excludeKey}) async {
    final keys = [StorageKeys.secretCode, StorageKeys.decoyCode, StorageKeys.deleteCode];
    for (final key in keys) {
      if (key == excludeKey) continue;
      final stored = await _storage.read(key: key);
      if (stored == null) continue;
      // Check exact match
      if (await _verifySecret(candidate, stored)) return true;
    }
    return false;
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

  // --- Push Privacy Mode ---

  /// When enabled, FCM push notifications are disabled and the app
  /// polls for messages with randomized intervals instead. This prevents
  /// the push notification provider (Google/Apple) from learning when
  /// messages are received or their frequency patterns.
  Future<void> setPushPrivacyEnabled(bool enabled) async {
    await _storage.write(
      key: StorageKeys.pushPrivacyMode,
      value: enabled.toString(),
    );
  }

  Future<bool> isPushPrivacyEnabled() async {
    final value = await _storage.read(key: StorageKeys.pushPrivacyMode);
    return value == 'true';
  }

  // --- Anzeigesprache ---

  /// Die gewaehlte Sprache als Code ('en', 'de', 'es', 'it', 'pt', 'fr').
  /// `null`, solange noch keine Wahl getroffen wurde — dann gilt Englisch.
  Future<String?> getLanguageCode() async {
    return _storage.read(key: StorageKeys.languageCode);
  }

  Future<void> setLanguageCode(String code) async {
    await _storage.write(key: StorageKeys.languageCode, value: code);
  }

  // --- Receipt Privacy Settings ---

  /// Delivery receipts: inform sender that message was received.
  /// Default: disabled (maximum privacy — sender learns nothing about delivery).
  Future<void> setDeliveryReceiptsEnabled(bool enabled) async {
    await _storage.write(
      key: StorageKeys.deliveryReceiptsEnabled,
      value: enabled.toString(),
    );
  }

  Future<bool> isDeliveryReceiptsEnabled() async {
    final value = await _storage.read(key: StorageKeys.deliveryReceiptsEnabled);
    return value == 'true'; // Default: false (disabled)
  }

  /// Read receipts: inform sender that message was read.
  /// Default: disabled (maximum privacy — sender learns nothing about read state).
  Future<void> setReadReceiptsEnabled(bool enabled) async {
    await _storage.write(
      key: StorageKeys.readReceiptsEnabled,
      value: enabled.toString(),
    );
  }

  Future<bool> isReadReceiptsEnabled() async {
    final value = await _storage.read(key: StorageKeys.readReceiptsEnabled);
    return value == 'true'; // Default: false (disabled)
  }

  // --- Vault Password (hashed, brute-force protected) ---

  /// Maximum vault password attempts before emergency wipe.
  static const int maxVaultAttempts = 5;

  /// Exponential delay base: 2^failCount seconds.
  /// 1→2s, 2→4s, 3→8s, 4→16s
  static Duration getVaultDelay(int failCount) {
    if (failCount <= 0) return Duration.zero;
    final seconds = 1 << failCount; // 2^failCount
    return Duration(seconds: seconds.clamp(0, 120));
  }

  Future<void> setVaultPassword(String password) async {
    final hashed = await _hashSecret(password);
    await _storage.write(key: StorageKeys.vaultPassword, value: hashed);
    await _storage.write(key: StorageKeys.vaultPasswordEnabled, value: 'true');
    // Reset fail counter on password change
    await resetVaultFailCount();
  }

  Future<void> removeVaultPassword() async {
    await _storage.delete(key: StorageKeys.vaultPassword);
    await _storage.write(key: StorageKeys.vaultPasswordEnabled, value: 'false');
    await resetVaultFailCount();
  }

  Future<bool> isVaultPasswordEnabled() async {
    final value = await _storage.read(key: StorageKeys.vaultPasswordEnabled);
    return value == 'true';
  }

  Future<bool> verifyVaultPassword(String input) async {
    final stored = await _storage.read(key: StorageKeys.vaultPassword);
    if (stored == null) return false;
    return _verifySecret(input, stored);
  }

  // --- Vault fail tracking (persistent) ---

  Future<int> getVaultFailCount() async {
    final value = await _storage.read(key: StorageKeys.vaultFailCount);
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<void> incrementVaultFailCount() async {
    final current = await getVaultFailCount();
    await _storage.write(
      key: StorageKeys.vaultFailCount,
      value: '${current + 1}',
    );
    await _storage.write(
      key: StorageKeys.vaultLastFailTime,
      value: '${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  Future<void> resetVaultFailCount() async {
    await _storage.delete(key: StorageKeys.vaultFailCount);
    await _storage.delete(key: StorageKeys.vaultLastFailTime);
  }

  /// Returns the remaining lockout duration, or Duration.zero if not locked.
  Future<Duration> getVaultLockoutRemaining() async {
    final failCount = await getVaultFailCount();
    if (failCount <= 0) return Duration.zero;

    final lastFailStr = await _storage.read(key: StorageKeys.vaultLastFailTime);
    if (lastFailStr == null) return Duration.zero;

    final lastFail = DateTime.fromMillisecondsSinceEpoch(
      int.tryParse(lastFailStr) ?? 0,
    );
    final delay = getVaultDelay(failCount);
    final unlockAt = lastFail.add(delay);
    final remaining = unlockAt.difference(DateTime.now());

    return remaining.isNegative ? Duration.zero : remaining;
  }

  // --- Wipe ---

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
