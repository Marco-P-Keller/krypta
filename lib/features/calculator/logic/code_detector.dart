import '../../../services/storage/secure_storage_service.dart';

enum CodeResult { none, secret, delete }

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
  /// Security: EVERY code is ALWAYS verified regardless of matches.
  /// This prevents timing side-channels — an observer cannot determine
  /// which code position matched by measuring response time. Entscheidend
  /// ist, dass alle Pruefungen laufen, nicht wie viele es sind: mit dem
  /// Ausbau des Tarn-Codes sind es zwei statt drei, die Eigenschaft bleibt.
  /// Priority is preserved: delete > secret.
  Future<CodeResult> checkCode(String displayValue) async {
    final cleaned = displayValue.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return CodeResult.none;

    // Always run every verification to normalize timing.
    // Each Argon2id hash takes ~200ms+ so timing differences would be
    // observable without this constant-work approach.
    final results = await Future.wait([
      _storage.verifyDeleteCode(cleaned),
      _storage.verifySecretCode(cleaned),
    ]);

    // Priority: delete > secret
    if (results[0]) return CodeResult.delete;
    if (results[1]) return CodeResult.secret;

    return CodeResult.none;
  }
}
