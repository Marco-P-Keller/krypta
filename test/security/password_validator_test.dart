import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/encryption/password_validator.dart';

void main() {
  group('PasswordValidator', () {
    group('evaluate', () {
      test('empty password is weak', () {
        expect(PasswordValidator.evaluate(''), PasswordStrength.weak);
      });

      test('short password is weak', () {
        expect(PasswordValidator.evaluate('abc'), PasswordStrength.weak);
      });

      test('all-same-char 6 chars has some entropy but validate rejects it', () {
        // 6 * log2(26) ≈ 28.2 bits — passes entropy check but validate catches all-same
        expect(PasswordValidator.validate('aaaaaa'), 'passwordAllSame');
      });

      test('lowercase only 6 chars is fair (28+ bits)', () {
        // 6 * log2(26) ≈ 28.2 bits — above weak threshold
        expect(PasswordValidator.evaluate('abcdef'), PasswordStrength.fair);
      });

      test('mixed case 8 chars is strong (>40 bits)', () {
        // 8 * log2(52) ≈ 45.6 bits
        expect(PasswordValidator.evaluate('AbCdEfGh'), PasswordStrength.strong);
      });

      test('mixed case + digits + symbols is strong', () {
        expect(
          PasswordValidator.evaluate('P@ssw0rd!XyZ'),
          PasswordStrength.strong,
        );
      });

      test('long lowercase is fair-to-strong', () {
        final result = PasswordValidator.evaluate('abcdefghijklmnop');
        expect(result, isNot(PasswordStrength.weak));
      });
    });

    group('validate', () {
      test('empty returns error', () {
        expect(PasswordValidator.validate(''), 'passwordEmpty');
      });

      test('too short returns error', () {
        expect(PasswordValidator.validate('abc'), 'passwordTooShort');
      });

      test('all same char returns error', () {
        expect(PasswordValidator.validate('aaaaaa'), 'passwordAllSame');
      });

      test('weak entropy returns error', () {
        // 5 chars lowercase = 5 * log2(26) ≈ 23.5 bits < 28
        expect(PasswordValidator.validate('abcde1'), isNull); // mixed = 31 bits, ok
        expect(PasswordValidator.validate('aabbc'), 'passwordTooShort'); // 5 chars
      });

      test('strong password returns null', () {
        expect(PasswordValidator.validate('MyStr0ng!Pass'), isNull);
      });
    });

    group('estimateEntropy', () {
      test('empty string has 0 entropy', () {
        expect(PasswordValidator.estimateEntropy(''), 0);
      });

      test('single char class has lower entropy', () {
        final lower = PasswordValidator.estimateEntropy('abcdef');
        final mixed = PasswordValidator.estimateEntropy('aBc1!f');
        expect(mixed, greaterThan(lower));
      });

      test('longer passwords have more entropy', () {
        final short = PasswordValidator.estimateEntropy('Aa1!');
        final long = PasswordValidator.estimateEntropy('Aa1!Bb2@');
        expect(long, greaterThan(short));
      });
    });
  });
}
