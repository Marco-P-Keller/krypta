/// Formal session failure policy with typed error classes.
///
/// Every security-related failure maps to a concrete error type with a
/// defined [SessionErrorPolicy]. This replaces ad-hoc `catch (_)` blocks
/// with explicit behavior per failure category.
///
/// Policy hierarchy (most → least severe):
/// 1. [destroySession] — cryptographic compromise, session must be destroyed
/// 2. [blockUntilVerified] — identity issue, block until user re-verifies
/// 3. [rejectMessage] — single message rejected, session survives
/// 4. [retryTransient] — network/timing issue, retry with backoff
library;

/// Defines what the system must do when a session error occurs.
enum SessionErrorPolicy {
  /// Destroy the session, delete ratchet state, block sending.
  /// Used for: signature failures, zero shared secrets, key compromise.
  destroySession,

  /// Block all communication until the user re-verifies the contact.
  /// Used for: key changes, identity mismatches.
  blockUntilVerified,

  /// Reject the specific message but keep the session alive.
  /// Used for: decryption failures, replay detection, padding errors.
  rejectMessage,

  /// Transient failure — retry with exponential backoff.
  /// Used for: network errors, server timeouts.
  retryTransient,
}

/// Base class for all session-related security errors.
sealed class SessionError implements Exception {
  /// Human-readable description (never shown to user — for logs only).
  String get message;

  /// The mandated response policy.
  SessionErrorPolicy get policy;

  /// Error category for structured logging.
  String get category;

  @override
  String toString() => '$category: $message [policy=$policy]';
}

// ─── Cryptographic Errors (destroySession) ──────────────────────────────────

/// Signed prekey signature verification failed.
/// Indicates a possible MITM attack on the key exchange.
class SignatureVerificationError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.destroySession;
  @override
  String get category => 'SIGNATURE_FAIL';

  SignatureVerificationError(this.message);
}

/// DH computation produced a zero shared secret (low-order point attack).
class ZeroSharedSecretError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.destroySession;
  @override
  String get category => 'ZERO_SECRET';

  ZeroSharedSecretError(this.message);
}

/// Invalid key material (wrong length, malformed encoding).
class InvalidKeyMaterialError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.destroySession;
  @override
  String get category => 'INVALID_KEY';

  InvalidKeyMaterialError(this.message);
}

/// PreKey bundle is v1 (no signing key) — cryptographically broken.
class LegacyBundleError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.destroySession;
  @override
  String get category => 'LEGACY_BUNDLE';

  LegacyBundleError(this.message);
}

// ─── Identity Errors (blockUntilVerified) ───────────────────────────────────

/// Contact's identity key has changed since last verification.
class KeyChangeDetectedError extends SessionError {
  @override
  final String message;
  final String contactId;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.blockUntilVerified;
  @override
  String get category => 'KEY_CHANGED';

  KeyChangeDetectedError(this.message, {required this.contactId});
}

/// QR-scanned key does not match the server-provided key.
class KeyMismatchError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.blockUntilVerified;
  @override
  String get category => 'KEY_MISMATCH';

  KeyMismatchError(this.message);
}

// ─── Message Errors (rejectMessage) ─────────────────────────────────────────

/// Message decryption failed (wrong key, tampered ciphertext, bad MAC).
class DecryptionFailedError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.rejectMessage;
  @override
  String get category => 'DECRYPT_FAIL';

  DecryptionFailedError(this.message);
}

/// Too many skipped messages in ratchet (DoS protection).
class RatchetSkipLimitError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.rejectMessage;
  @override
  String get category => 'SKIP_LIMIT';

  RatchetSkipLimitError(this.message);
}

/// Replay/duplicate message detected.
class ReplayDetectedError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.rejectMessage;
  @override
  String get category => 'REPLAY';

  ReplayDetectedError(this.message);
}

/// Invalid message version (e.g., v1 when only v2+ is accepted).
class UnsupportedVersionError extends SessionError {
  @override
  final String message;
  final int version;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.rejectMessage;
  @override
  String get category => 'VERSION_REJECT';

  UnsupportedVersionError(this.message, {required this.version});
}

/// Message padding is invalid (possible tampering or protocol mismatch).
class PaddingError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.rejectMessage;
  @override
  String get category => 'PADDING_FAIL';

  PaddingError(this.message);
}

// ─── Transient Errors (retryTransient) ──────────────────────────────────────

/// Network or server communication failure.
class NetworkError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.retryTransient;
  @override
  String get category => 'NETWORK';

  NetworkError(this.message);
}

/// PreKey bundle not available on server (contact hasn't published one yet).
class BundleNotAvailableError extends SessionError {
  @override
  final String message;
  @override
  SessionErrorPolicy get policy => SessionErrorPolicy.retryTransient;
  @override
  String get category => 'NO_BUNDLE';

  BundleNotAvailableError(this.message);
}
