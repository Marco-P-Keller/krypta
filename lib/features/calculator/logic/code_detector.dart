import '../../../services/storage/secure_storage_service.dart';

enum CodeResult { none, secret, decoy, delete }

/// Detects if the user has entered a special code on the calculator.
///
/// Checks the current display value against stored codes.
/// Uses a buffer that tracks the sequence of digits entered via "=".
class CodeDetector {
  final SecureStorageService _storage;

  String? _cachedSecretCode;
  String? _cachedDecoyCode;
  String? _cachedDeleteCode;

  CodeDetector({required SecureStorageService storage}) : _storage = storage;

  Future<void> loadCodes() async {
    _cachedSecretCode = await _storage.getSecretCode();
    _cachedDecoyCode = await _storage.getDecoyCode();
    _cachedDeleteCode = await _storage.getDeleteCode();
  }

  /// Check the current display value against known codes.
  /// Called when the user presses "=" on the calculator.
  CodeResult checkCode(String displayValue) {
    final cleaned = displayValue.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleaned.isEmpty) return CodeResult.none;

    if (_cachedDeleteCode != null && cleaned == _cachedDeleteCode) {
      return CodeResult.delete;
    }

    if (_cachedSecretCode != null && cleaned == _cachedSecretCode) {
      return CodeResult.secret;
    }

    if (_cachedDecoyCode != null && cleaned == _cachedDecoyCode) {
      return CodeResult.decoy;
    }

    return CodeResult.none;
  }

  void clearCache() {
    _cachedSecretCode = null;
    _cachedDecoyCode = null;
    _cachedDeleteCode = null;
  }
}
