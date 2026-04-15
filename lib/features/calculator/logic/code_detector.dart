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
  Future<CodeResult> checkCode(String displayValue) async {
    final cleaned = displayValue.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return CodeResult.none;

    // Delete code checked first — highest priority
    if (await _storage.verifyDeleteCode(cleaned)) return CodeResult.delete;
    if (await _storage.verifySecretCode(cleaned)) return CodeResult.secret;
    if (await _storage.verifyDecoyCode(cleaned)) return CodeResult.decoy;

    return CodeResult.none;
  }
}
