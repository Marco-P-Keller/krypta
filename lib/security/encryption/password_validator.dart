import 'dart:math';

/// Password strength levels for password-protected messages.
enum PasswordStrength {
  /// Unacceptable — fewer than 6 chars or all same character.
  weak,

  /// Meets minimum threshold but not ideal.
  fair,

  /// Good entropy — mixed character classes, sufficient length.
  strong,
}

/// Validates and evaluates password strength for password-protected messages.
///
/// Uses entropy estimation based on character class pool size and length.
/// This is defense-in-depth — the UI should prevent weak passwords,
/// but the encryption layer rejects them as a backstop.
class PasswordValidator {
  PasswordValidator._();

  /// Evaluate password strength based on estimated entropy.
  static PasswordStrength evaluate(String password) {
    final entropy = estimateEntropy(password);
    if (entropy < 28) return PasswordStrength.weak;
    if (entropy < 40) return PasswordStrength.fair;
    return PasswordStrength.strong;
  }

  /// Returns null if password is acceptable, or an error key if too weak.
  ///
  /// Call before encrypting a password-protected message.
  /// Rejects: empty, < 6 chars, all-same-char, < 28 bits entropy.
  static String? validate(String password) {
    if (password.isEmpty) return 'passwordEmpty';
    if (password.length < 6) return 'passwordTooShort';
    if (password.split('').toSet().length == 1) return 'passwordAllSame';
    if (estimateEntropy(password) < 28) return 'passwordTooWeak';
    return null;
  }

  /// Estimate bits of entropy: log2(poolSize ^ length).
  ///
  /// Pool size is the union of character classes present:
  /// - lowercase (26), uppercase (26), digits (10), symbols (~32)
  static double estimateEntropy(String password) {
    if (password.isEmpty) return 0;

    var poolSize = 0;
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSymbol = password.contains(RegExp(r'[^a-zA-Z0-9]'));

    if (hasLower) poolSize += 26;
    if (hasUpper) poolSize += 26;
    if (hasDigit) poolSize += 10;
    if (hasSymbol) poolSize += 32;

    if (poolSize == 0) poolSize = 26; // fallback

    return password.length * (log(poolSize) / log(2));
  }
}
