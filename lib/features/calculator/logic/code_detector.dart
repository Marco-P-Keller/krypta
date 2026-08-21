import '../../../services/storage/secure_storage_service.dart';

enum CodeResult { none, secret, decoy, delete }

/// Detects if the user has entered a special code on the calculator.
///
/// Security: codes are stored as Argon2id hashes — this class never
/// sees plaintext codes in memory after setup. Each check runs the
/// Argon2id KDF against the stored hash.
///
/// Delete code is verified FIRST to prevent an attacker from cancelling
/// a wipe by guessing the secret code at the same moment.
class CodeDetector {
  final SecureStorageService _storage;

  CodeDetector({required SecureStorageService storage}) : _storage = storage;

  /// Check the current display value against stored (hashed) codes.
  /// Called when the user presses "=" on the calculator.
  /// Returns the matched CodeResult, or [CodeResult.none].
  ///
  /// Security: All three codes are ALWAYS verified regardless of matches.
  /// This prevents timing side-channels — an observer cannot determine
  /// which code position matched by measuring response time.
  /// Priority is preserved: delete > secret > decoy.
  Future<CodeResult> checkCode(String displayValue) async {
    final cleaned = displayValue.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return CodeResult.none;

    // Always run all three verifications to normalize timing.
    // Each Argon2id hash takes ~200ms+ so timing differences would be
    // observable without this constant-work approach.
    final results = await Future.wait([
      _storage.verifyDeleteCode(cleaned),
      _storage.verifySecretCode(cleaned),
      _storage.verifyDecoyCode(cleaned),
    ]);

    // Priority: delete > secret > decoy
    if (results[0]) return CodeResult.delete;
    if (results[1]) return CodeResult.secret;
    if (results[2]) return CodeResult.decoy;

    return CodeResult.none;
  }
}
