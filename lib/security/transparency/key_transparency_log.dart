import 'dart:convert';
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

  /// H1-Crypto (audit 2026-05): the commitment is signed with a different
  /// `signingPublicKey` than the chain head's. This indicates a possible
  /// MITM where the server (or anyone with write access to the
  /// transparency log) attempts to substitute the Ed25519 signing key
  /// while keeping the X25519 identity key unchanged. Without TOFU on
  /// the signing key the X25519 identity (verified via Safety Number)
  /// would still match while signature provenance silently rotates.
  signingKeyChanged,

  /// H1-Crypto / Codex round-5 P1: the chain has no pin yet and the
  /// caller is trying to bootstrap with a legacy v1 commitment. v1's
  /// signature does not cover `signingPublicKey`, so a malicious server
  /// could forge a fresh v1 commitment with their own Ed25519 key for
  /// any verified identity and have it accepted as the initial pin.
  /// Initial pinning is therefore only allowed from v2+ commitments
  /// where the signing key is signature-bound.
  legacyBootstrapRejected,
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

  /// In-memory cache: userId → pinned Ed25519 signingPublicKey (TOFU).
  /// Loaded lazily on first append; persisted under [_pinPrefix].
  final Map<String, Uint8List> _signingPins = {};

  static const String _storagePrefix = 'kt_log_';

  /// H1-Crypto (audit 2026-05): TOFU pin storage for the Ed25519
  /// signingPublicKey, separated from the chain. The pin is the source of
  /// truth for "which signing key is allowed to extend this chain". Storing
  /// it outside the chain prevents the v1 weakness Codex round-2 P1 raised:
  /// in a v1 commitment the signingPublicKey field is not covered by the
  /// signature, so trusting `log.last.signingPublicKey` as TOFU baseline
  /// would itself be tamperable. The pin is set on first append (genesis)
  /// and verified on every subsequent append.
  static const String _pinPrefix = 'kt_pin_';

  KeyTransparencyLog({required EncryptedLocalStore store}) : _store = store;

  /// Load the pinned signingPublicKey for [userId], or null if not yet pinned.
  ///
  /// Codex round-3 P1 fix: on installs that pre-date the pin storage but
  /// already have a chain, the pin is bootstrapped from the existing
  /// `log.first.signingPublicKey`. Without this, the first post-upgrade
  /// append would have no pin to check against, and the attacker could
  /// supply their own commitment in the migration window and re-baseline
  /// the pin to themselves. The bootstrap binds the pin to the genesis
  /// signing key — which IS the best baseline available locally. For v2
  /// genesis this is signature-covered (strong); for legacy v1 genesis it
  /// is only as trusted as the storage integrity at chain-creation time
  /// (acknowledged residual; documented in the audit report).
  Future<Uint8List?> _loadPin(String userId) async {
    if (_signingPins.containsKey(userId)) return _signingPins[userId];
    final raw = await _store.loadData('$_pinPrefix$userId');
    if (raw is String) {
      try {
        final bytes = base64Decode(raw);
        _signingPins[userId] = bytes;
        return bytes;
      } catch (_) {
        // fall through to bootstrap from chain
      }
    }
    // No persisted pin — bootstrap from the existing chain genesis if any.
    final log = await getLog(userId);
    if (log.isNotEmpty) {
      final bootstrapped =
          Uint8List.fromList(log.first.signingPublicKey);
      _signingPins[userId] = bootstrapped;
      await _store.saveData(
          '$_pinPrefix$userId', base64Encode(bootstrapped));
      return bootstrapped;
    }
    return null;
  }

  /// Persist [pin] as the locked signingPublicKey for [userId].
  Future<void> _savePin(String userId, Uint8List pin) async {
    _signingPins[userId] = pin;
    await _store.saveData('$_pinPrefix$userId', base64Encode(pin));
  }

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

    // 6. H1-Crypto: signing-key TOFU via separate pin. The pin lives outside
    // the chain so legacy v1 entries (whose signature does not cover
    // signingPublicKey) cannot be used as a tamperable baseline. The pin is
    // bootstrapped on the first appended commitment; afterwards every append
    // must match it exactly.
    //
    // Codex round-5 P1: if the chain is empty AND no pin exists, the very
    // first append BOOTSTRAPS the pin. That bootstrap must come from a v2+
    // commitment whose signature actually covers signingPublicKey — a v1
    // initial commitment would let an attacker pin their own Ed25519 key
    // because v1's signature does not bind the signing pub.
    final pinned = await _loadPin(userId);
    if (pinned != null) {
      if (!_bytesEqual(commitment.signingPublicKey, pinned)) {
        return CommitmentVerifyResult.signingKeyChanged;
      }
    } else {
      // pinned == null implies no persisted pin AND _loadPin found no chain
      // to bootstrap from (otherwise it would have written one). This is a
      // brand-new chain; we will set the pin from this commitment, so it
      // must come from a layout that signs over signingPublicKey.
      if (commitment.version < 2) {
        return CommitmentVerifyResult.legacyBootstrapRejected;
      }
    }

    // All checks passed — append, persist, and (if first append) lock the pin.
    log.add(commitment);
    await _persistLog(userId, log);
    if (pinned == null) {
      await _savePin(userId, commitment.signingPublicKey);
    }
    return CommitmentVerifyResult.valid;
  }

  /// Verify a full chain from genesis to head without appending.
  ///
  /// Used for audit: loads all commitments and verifies every link.
  /// Returns the index of the first broken link, or -1 if chain is intact.
  ///
  /// H1-Crypto / Codex round-2 P2: the chain's Ed25519 signingPublicKey must
  /// be consistent across all links. Any rotation mid-chain indicates either
  /// log tampering or a server-side key substitution attack and the chain
  /// is reported broken at the rotation point.
  Future<int> auditChain(String userId) async {
    final log = await getLog(userId);
    if (log.isEmpty) return -1;

    // Verify genesis
    if (!log.first.isGenesis) return 0;
    final genesisValid = await log.first.verifySignature();
    if (!genesisValid) return 0;

    // Codex R8 P2: prefer the persisted pin as the audit baseline. The pin
    // is bound by the strong path (v2 sig covers signingPub) or — for legacy
    // installs — bootstrapped from genesis at first access. Either way it
    // is more authoritative than re-reading log.first which, for legacy v1
    // chains, has unsigned signingPublicKey fields and could be uniformly
    // tampered to bypass this consistency check.
    final pinned = await _loadPin(userId);
    final expectedSigningPub = pinned ?? log.first.signingPublicKey;

    // Codex R10 P2: when a pin exists, check the genesis entry too. Without
    // this a single-entry chain (or any chain whose post-genesis entries
    // still match the pin) could have its v1 genesis signingPublicKey
    // tampered without detection. We start the inner loop at index 1; the
    // genesis must be validated against the pin here.
    if (pinned != null &&
        !_bytesEqual(log.first.signingPublicKey, pinned)) {
      return 0;
    }

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

      // H1-Crypto: signingPublicKey must not rotate within an audited chain.
      if (!_bytesEqual(curr.signingPublicKey, expectedSigningPub)) return i;
    }

    return -1; // Chain is intact
  }

  /// Clear the log for a user (e.g., on contact removal or wipe).
  ///
  /// Also clears the H1-Crypto signing-key pin so a re-add of the same
  /// userId starts a fresh TOFU bootstrap rather than locking against a
  /// stale pin.
  Future<void> clearLog(String userId) async {
    _logs.remove(userId);
    _signingPins.remove(userId);
    await _store.saveData('$_storagePrefix$userId', null);
    await _store.saveData('$_pinPrefix$userId', null);
  }

  /// Clear all transparency logs (full wipe).
  ///
  /// Clears in-memory cache. Persistent storage for individual logs
  /// is cleaned up by EncryptedLocalStore.wipeAll() during emergency wipe.
  /// For targeted cleanup, use [clearLog] per userId.
  void clearAll() {
    _logs.clear();
    _signingPins.clear();
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
