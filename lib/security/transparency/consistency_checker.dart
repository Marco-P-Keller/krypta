import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'key_transparency_log.dart';

/// Result of a consistency check between two views of a key commitment chain.
enum ConsistencyResult {
  /// Both views agree — same epoch and commit hash.
  consistent,

  /// Local view is behind — the remote has seen more commitments.
  /// Not an attack; local needs to fetch new commitments.
  localBehind,

  /// Remote view is behind — we have more commitments than the remote.
  /// Not an attack; remote needs to fetch new commitments.
  remoteBehind,

  /// SPLIT VIEW DETECTED: same epoch but different commit hashes.
  /// The server is serving different key material to different users.
  /// This is the attack Key Transparency is designed to detect.
  splitView,

  /// No remote proof available — cannot verify consistency.
  noProof,
}

/// A compact proof of a user's latest observed key commitment state.
///
/// Exchanged between clients as a gossip mechanism. Each message can
/// carry the sender's view of the recipient's key chain head, enabling
/// passive split-view detection without a dedicated auditor.
///
/// Size: ~80 bytes serialized (userId + epoch + 32-byte hash).
class ConsistencyProof {
  /// The user whose key chain this proof describes.
  final String userId;

  /// The latest epoch observed.
  final int epoch;

  /// The commitHash of the commitment at [epoch].
  final Uint8List commitHash;

  ConsistencyProof({
    required this.userId,
    required this.epoch,
    required this.commitHash,
  });

  Map<String, dynamic> toMap() => {
        'u': userId,
        'e': epoch,
        'h': base64Encode(commitHash),
      };

  factory ConsistencyProof.fromMap(Map<String, dynamic> map) {
    return ConsistencyProof(
      userId: map['u'] as String,
      epoch: map['e'] as int,
      commitHash: base64Decode(map['h'] as String),
    );
  }
}

/// Cross-client key consistency verification.
///
/// Security model:
/// - Clients exchange [ConsistencyProof]s during message exchange (gossip).
/// - If the server shows different keys to different users (split-view),
///   the proofs will diverge at the same epoch → [ConsistencyResult.splitView].
/// - Even without a dedicated auditor server, pairwise gossip detects
///   targeted MITM within one message round-trip.
///
/// Threat coverage:
/// - Server swaps key for one user: detected on next message exchange
/// - Server delays commitment delivery: detected as localBehind/remoteBehind
/// - Server completely fabricates a chain: detected by signature verification
///   in KeyTransparencyLog (proofs reference commitment hashes that must
///   trace back to valid Ed25519 signatures)
class ConsistencyChecker {
  final KeyTransparencyLog _log;

  ConsistencyChecker({required KeyTransparencyLog log}) : _log = log;

  /// Build a consistency proof for a contact's key chain from our local view.
  ///
  /// Returns null if we have no commitments for this user.
  Future<ConsistencyProof?> buildProof(String userId) async {
    final head = await _log.getHead(userId);
    if (head == null) return null;

    return ConsistencyProof(
      userId: userId,
      epoch: head.epoch,
      commitHash: head.commitHash,
    );
  }

  /// Check a received proof against our local view.
  ///
  /// Called when receiving a message that includes a consistency proof
  /// about our own key chain (the sender tells us what they see for us).
  Future<ConsistencyResult> verifyProof(ConsistencyProof remoteProof) async {
    final localHead = await _log.getHead(remoteProof.userId);

    if (localHead == null) {
      return ConsistencyResult.noProof;
    }

    final localEpoch = localHead.epoch;
    final remoteEpoch = remoteProof.epoch;

    if (localEpoch == remoteEpoch) {
      // Same epoch — hashes MUST match
      if (_bytesEqual(localHead.commitHash, remoteProof.commitHash)) {
        return ConsistencyResult.consistent;
      }
      // CRITICAL: Same epoch, different hash = split-view attack
      return ConsistencyResult.splitView;
    }

    if (localEpoch < remoteEpoch) {
      return ConsistencyResult.localBehind;
    }

    // localEpoch > remoteEpoch: check if the remote's hash matches
    // our log at that epoch
    final localLog = await _log.getLog(remoteProof.userId);
    final matchAtEpoch = localLog
        .where((c) => c.epoch == remoteEpoch)
        .toList();

    if (matchAtEpoch.isEmpty) {
      // We don't have that epoch — gap in our log
      return ConsistencyResult.remoteBehind;
    }

    if (_bytesEqual(matchAtEpoch.first.commitHash, remoteProof.commitHash)) {
      // Remote is behind but consistent with our chain at that point
      return ConsistencyResult.remoteBehind;
    }

    // Same epoch exists in both views but hashes differ → split view
    return ConsistencyResult.splitView;
  }

  /// Generate a mutual consistency exchange payload.
  ///
  /// When sending a message to [recipientId], include proofs for:
  /// 1. Our view of the recipient's key chain (so they can verify consistency)
  /// 2. Our own chain head (so they can verify our key hasn't been swapped)
  ///
  /// Returns a compact map suitable for embedding in message metadata.
  Future<Map<String, dynamic>?> buildGossipPayload({
    required String localUserId,
    required String recipientId,
  }) async {
    final recipientProof = await buildProof(recipientId);
    final selfProof = await buildProof(localUserId);

    if (recipientProof == null && selfProof == null) return null;

    return {
      if (recipientProof != null) 'rp': recipientProof.toMap(),
      if (selfProof != null) 'sp': selfProof.toMap(),
    };
  }

  /// Process a received gossip payload from a message.
  ///
  /// Checks consistency of:
  /// 1. The sender's view of our key chain ('rp' — are they seeing our real keys?)
  /// 2. The sender's own chain head ('sp' — has the server swapped their key?)
  ///
  /// Returns a map of userId → ConsistencyResult for each checked proof.
  Future<Map<String, ConsistencyResult>> processGossipPayload(
      Map<String, dynamic> payload) async {
    final results = <String, ConsistencyResult>{};

    if (payload.containsKey('rp')) {
      final proof = ConsistencyProof.fromMap(
          payload['rp'] as Map<String, dynamic>);
      results[proof.userId] = await verifyProof(proof);
    }

    if (payload.containsKey('sp')) {
      final proof = ConsistencyProof.fromMap(
          payload['sp'] as Map<String, dynamic>);
      results[proof.userId] = await verifyProof(proof);
    }

    return results;
  }

  /// Compute a fingerprint of the entire chain for visual comparison.
  ///
  /// Users can compare this value out-of-band to verify they see the
  /// same transparency history. SHA-256 of all commit hashes concatenated.
  Future<String> chainFingerprint(String userId) async {
    final log = await _log.getLog(userId);
    if (log.isEmpty) return '(empty)';

    final allHashes = <int>[];
    for (final c in log) {
      allHashes.addAll(c.commitHash);
    }
    final digest = crypto.sha256.convert(allHashes);
    return digest.bytes
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
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
