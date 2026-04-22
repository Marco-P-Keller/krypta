import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/session/session_errors.dart';

void main() {
  group('Session Error Policy Mapping', () {
    test('SignatureVerificationError → destroySession', () {
      final e = SignatureVerificationError('bad sig');
      expect(e.policy, SessionErrorPolicy.destroySession);
      expect(e.category, 'SIGNATURE_FAIL');
      expect(e.message, 'bad sig');
      expect(e.toString(), contains('SIGNATURE_FAIL'));
    });

    test('ZeroSharedSecretError → destroySession', () {
      final e = ZeroSharedSecretError('all zeros');
      expect(e.policy, SessionErrorPolicy.destroySession);
      expect(e.category, 'ZERO_SECRET');
    });

    test('InvalidKeyMaterialError → destroySession', () {
      final e = InvalidKeyMaterialError('wrong length');
      expect(e.policy, SessionErrorPolicy.destroySession);
      expect(e.category, 'INVALID_KEY');
    });

    test('LegacyBundleError → destroySession', () {
      final e = LegacyBundleError('v1 bundle');
      expect(e.policy, SessionErrorPolicy.destroySession);
      expect(e.category, 'LEGACY_BUNDLE');
    });

    test('KeyChangeDetectedError → blockUntilVerified', () {
      final e = KeyChangeDetectedError('key changed', contactId: 'user123');
      expect(e.policy, SessionErrorPolicy.blockUntilVerified);
      expect(e.category, 'KEY_CHANGED');
      expect(e.contactId, 'user123');
    });

    test('KeyMismatchError → blockUntilVerified', () {
      final e = KeyMismatchError('server vs QR');
      expect(e.policy, SessionErrorPolicy.blockUntilVerified);
      expect(e.category, 'KEY_MISMATCH');
    });

    test('DecryptionFailedError → rejectMessage', () {
      final e = DecryptionFailedError('bad MAC');
      expect(e.policy, SessionErrorPolicy.rejectMessage);
      expect(e.category, 'DECRYPT_FAIL');
    });

    test('RatchetSkipLimitError → rejectMessage', () {
      final e = RatchetSkipLimitError('too many skips');
      expect(e.policy, SessionErrorPolicy.rejectMessage);
      expect(e.category, 'SKIP_LIMIT');
    });

    test('ReplayDetectedError → rejectMessage', () {
      final e = ReplayDetectedError('duplicate msg');
      expect(e.policy, SessionErrorPolicy.rejectMessage);
      expect(e.category, 'REPLAY');
    });

    test('UnsupportedVersionError → rejectMessage', () {
      final e = UnsupportedVersionError('v1 not supported', version: 1);
      expect(e.policy, SessionErrorPolicy.rejectMessage);
      expect(e.category, 'VERSION_REJECT');
      expect(e.version, 1);
    });

    test('PaddingError → rejectMessage', () {
      final e = PaddingError('bad padding');
      expect(e.policy, SessionErrorPolicy.rejectMessage);
      expect(e.category, 'PADDING_FAIL');
    });

    test('NetworkError → retryTransient', () {
      final e = NetworkError('timeout');
      expect(e.policy, SessionErrorPolicy.retryTransient);
      expect(e.category, 'NETWORK');
    });

    test('BundleNotAvailableError → retryTransient', () {
      final e = BundleNotAvailableError('no bundle');
      expect(e.policy, SessionErrorPolicy.retryTransient);
      expect(e.category, 'NO_BUNDLE');
    });
  });

  group('Session Error Hierarchy', () {
    test('all error types are SessionError', () {
      final errors = <SessionError>[
        SignatureVerificationError('test'),
        ZeroSharedSecretError('test'),
        InvalidKeyMaterialError('test'),
        LegacyBundleError('test'),
        KeyChangeDetectedError('test', contactId: 'c'),
        KeyMismatchError('test'),
        DecryptionFailedError('test'),
        RatchetSkipLimitError('test'),
        ReplayDetectedError('test'),
        UnsupportedVersionError('test', version: 1),
        PaddingError('test'),
        NetworkError('test'),
        BundleNotAvailableError('test'),
      ];

      for (final e in errors) {
        expect(e, isA<SessionError>());
        expect(e, isA<Exception>());
        expect(e.message, isNotEmpty);
        expect(e.category, isNotEmpty);
        expect(e.toString(), contains(e.category));
      }
    });

    test('policy severity ordering is correct', () {
      // destroySession is the most severe
      expect(SessionErrorPolicy.destroySession.index, 0);
      // blockUntilVerified is second
      expect(SessionErrorPolicy.blockUntilVerified.index, 1);
      // rejectMessage is third
      expect(SessionErrorPolicy.rejectMessage.index, 2);
      // retryTransient is least severe
      expect(SessionErrorPolicy.retryTransient.index, 3);
    });
  });

  group('Policy-based error handling', () {
    test('switch exhaustiveness — all policies covered', () {
      // This test verifies that all policies can be matched in a switch.
      // If a new policy is added, this test must be updated.
      for (final policy in SessionErrorPolicy.values) {
        final result = switch (policy) {
          SessionErrorPolicy.destroySession => 'destroy',
          SessionErrorPolicy.blockUntilVerified => 'block',
          SessionErrorPolicy.rejectMessage => 'reject',
          SessionErrorPolicy.retryTransient => 'retry',
        };
        expect(result, isNotEmpty);
      }
    });
  });
}
