import 'dart:typed_data';
import '../../services/storage/encrypted_local_store.dart';
import 'key_commitment.dart';

/// Result of verifying a commitment against the local log.
enum CommitmentVerifyResult {
  /// Commitment is valid and extends the chain.
  valid,

  /// Signature verification failed — commitment may be forged.
  signatureInvalid,

  /// Chain link broken — previousCommitHash doesn't match expected.
  chainBroken,

  /// Epoch is not strictly increasing — replay or gap detected.
  epochViolation,

  /// Identity key in commitment doesn't match expected key for this user.
  keyMismatch,

  /// Commitment data is malformed (wrong lengths, missing fields).
  malformed,
}

/// Local auditable log of key commitments per contact.
///
/// Security model:
/// - Each contact has an ordered chain of commitments stored locally.
/// - Appending a new commitment requires: valid signature, correct chain link,
///   and strictly increasing epoch.
/// - The log is tamper-evident: breaking any link is detectable.
/// - Stored in EncryptedLocalStore (XChaCha20-Poly1305 at rest).
/// - Fail-closed: any verification failure rejects the commitment.
class KeyTransparencyLog {
  final EncryptedLocalStore _store;

  /// In-memory cache: userId → ordered list of commitments.
  final Map<String, List<KeyCommitment>> _logs = {};

  static const String _storagePrefix = 'kt_log_';

  KeyTransparencyLog({required EncryptedLocalStore store}) : _store = store;

  /// Load the commitment log for a user from encrypted storage.
  Future<List<KeyCommitment>> getLog(String userId) async {
    if (_logs.containsKey(userId)) return _logs[userId]!;

    final data = await _store.loadData('$_storagePrefix$userId');
    if (data == null) {
      _logs[userId] = [];
      return [];
    }

    try {
      final list = (data as List).cast<Map<String, dynamic>>();
      final commitments = list.map((m) => KeyCommitment.fromMap(m)).toList();
      _logs[userId] = commitments;
      return commitments;
    } catch (_) {
      _logs[userId] = [];
      return [];
    }
  }

  /// Get the latest commitment for a user, or null if none.
  Future<KeyCommitment?> getHead(String userId) async {
    final log = await getLog(userId);
    return log.isEmpty ? null : log.last;
  }

  /// Get the latest epoch for a user, or -1 if no commitments.
  Future<int> getLatestEpoch(String userId) async {
    final head = await getHead(userId);
    return head?.epoch ?? -1;
  }

  /// Get the commit hash of the latest commitment (chain head).
  /// Returns [KeyCommitment.genesisHash] if no commitments exist.
  Future<Uint8List> getHeadHash(String userId) async {
    final head = await getHead(userId);
    return head?.commitHash ?? KeyCommitment.genesisHash;
  }

  /// Verify and append a new commitment to the log.
  ///
  /// Verification steps (all must pass — fail-closed):
  /// 1. Structural validation (key lengths, non-empty signature)
  /// 2. Ed25519 signature verification
  /// 3. Epoch must be strictly greater than current head
  /// 4. previousCommitHash must match current head's commitHash
  /// 5. Identity key must match [expectedPublicKey] if provided
  ///
  /// Returns [CommitmentVerifyResult.valid] on success; the commitment
  /// is appended and persisted. Any other result means rejection.
  Future<CommitmentVerifyResult> verifyAndAppend({
    required String userId,
    required KeyCommitment commitment,
    Uint8List? expectedPublicKey,
  }) async {
    // 1. Structural validation
    if (commitment.identityPublicKey.length != 32 ||
        commitment.previousCommitHash.length != 32 ||
        commitment.signature.isEmpty ||
        commitment.signingPublicKey.length != 32) {
      return CommitmentVerifyResult.malformed;
    }

    // 2. Signature verification
    final sigValid = await commitment.verifySignature();
    if (!sigValid) return CommitmentVerifyResult.signatureInvalid;

    // 3. Epoch check
    final log = await getLog(userId);
    final expectedEpoch = log.isEmpty ? 0 : log.last.epoch + 1;
    if (commitment.epoch != expectedEpoch) {
      return CommitmentVerifyResult.epochViolation;
    }

    // 4. Chain link verification
    final expectedPrevHash = log.isEmpty
        ? KeyCommitment.genesisHash
        : log.last.commitHash;
    if (!commitment.verifiesAgainst(expectedPrevHash)) {
      return CommitmentVerifyResult.chainBroken;
    }

    // 5. Key match (optional but recommended)
    if (expectedPublicKey != null) {
      if (!_bytesEqual(commitment.identityPublicKey, expectedPublicKey)) {
        return CommitmentVerifyResult.keyMismatch;
      }
    }

    // All checks passed — append and persist
    log.add(commitment);
    await _persistLog(userId, log);
    return CommitmentVerifyResult.valid;
  }

  /// Verify a full chain from genesis to head without appending.
  ///
  /// Used for audit: loads all commitments and verifies every link.
  /// Returns the index of the first broken link, or -1 if chain is intact.
  Future<int> auditChain(String userId) async {
    final log = await getLog(userId);
    if (log.isEmpty) return -1;

    // Verify genesis
    if (!log.first.isGenesis) return 0;
    final genesisValid = await log.first.verifySignature();
    if (!genesisValid) return 0;

    // Verify each subsequent link
    for (var i = 1; i < log.length; i++) {
      final prev = log[i - 1];
      final curr = log[i];

      // Epoch must be strictly increasing
      if (curr.epoch != prev.epoch + 1) return i;

      // Chain link
      if (!curr.verifiesAgainst(prev.commitHash)) return i;

      // Signature
      final valid = await curr.verifySignature();
      if (!valid) return i;
    }

    return -1; // Chain is intact
  }

  /// Clear the log for a user (e.g., on contact removal or wipe).
  Future<void> clearLog(String userId) async {
    _logs.remove(userId);
    await _store.saveData('$_storagePrefix$userId', null);
  }

  /// Clear all transparency logs (full wipe).
  ///
  /// Clears in-memory cache. Persistent storage for individual logs
  /// is cleaned up by EncryptedLocalStore.wipeAll() during emergency wipe.
  /// For targeted cleanup, use [clearLog] per userId.
  void clearAll() {
    _logs.clear();
  }

  Future<void> _persistLog(String userId, List<KeyCommitment> log) async {
    _logs[userId] = log;
    await _store.saveData(
      '$_storagePrefix$userId',
      log.map((c) => c.toMap()).toList(),
    );
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
