import 'ratchet_state.dart';

/// Receive-side enforcement for replay (`_seq`) and session-rollback (`_psid`)
/// protection inside decrypted v3 content payloads.
///
/// Sender writes:
/// - `_seq`: monotonic per-session sequence number (advances every send).
/// - `_psid`: the sender's previous session id; only meaningful in the first
///   message of a new session (where `_seq == 0`).
///
/// Receiver enforces:
/// - `_seq` must not already be in `recentRecvSeqs` (else replay).
/// - `_seq` must not be more than [seqWindow] below the highest seen
///   (else too-old — stale replay past the ratchet's own skip window).
/// - `_psid` (when `_seq == 0`) must not be in `peerSeenPsids`
///   (else session rollback).
///
/// The window [seqWindow] matches the Double Ratchet max-skip, so any reorder
/// the ratchet itself tolerates is tolerated here too.
///
/// **Scope:** only content messages carrying `_seq`. Control messages have
/// their own replay protection (`_controlCounter`) and HMAC authentication
/// derived from the shared ratchet state, so they deliberately bypass this
/// guard. v2 and v1 payloads pass through unchanged.
class ReplayGuard {
  ReplayGuard._();

  /// Reason codes (stable — used for logging and in tests).
  static const replaySeq = 'REPLAY_SEQ';
  static const missingSeq = 'MISSING_SEQ';
  static const rollbackPsid = 'ROLLBACK_PSID';
  static const seqTooOld = 'SEQ_TOO_OLD';

  /// How far below the highest seen seq we still accept — matches Double
  /// Ratchet's `_maxSkip` so we never reject a message the ratchet accepts.
  static const seqWindow = 200;

  /// Validate [innerPayload] against replay/rollback using [state].
  ///
  /// On accept: [ValidationResult.state] is the advanced state (seq added to
  /// window, optionally new psid). On reject: state is null, [rejectReason]
  /// holds the code. v2/v1 passthrough returns the input state unchanged.
  ///
  /// Cross-version note: v3 payloads from older clients may lack `_seq` /
  /// `_psid` (the fields were added during the security/hardening rollout
  /// while the wire version was kept at 3). Such payloads pass through
  /// unchanged — the ratchet's own AEAD authentication still applies, only
  /// the additional replay/rollback enforcement layered on top of v3 is
  /// skipped for legacy senders. Once both peers are on the new build, every
  /// real v3 payload carries `_seq` and is enforced normally.
  static ValidationResult validate({
    required RatchetState state,
    required Map<String, dynamic> innerPayload,
    required int version,
  }) {
    if (version < 3) return ValidationResult._accept(state);

    final seq = innerPayload['_seq'];
    if (seq is! int) {
      // Legacy v3 sender — accept without advancing replay state.
      return ValidationResult._accept(state);
    }

    if (state.recentRecvSeqs.contains(seq)) {
      return ValidationResult._reject(replaySeq);
    }
    if (seq < state.highestRecvSeq - seqWindow) {
      return ValidationResult._reject(seqTooOld);
    }

    // _psid is only meaningful for the FIRST message of a new session.
    // Peers carrying it in later messages do not bloat the rollback set.
    final psid = innerPayload['_psid'];
    final psidIsFirstMessage = seq == 0 && psid is String;
    if (psidIsFirstMessage && state.peerSeenPsids.contains(psid)) {
      return ValidationResult._reject(rollbackPsid);
    }

    final newSeqs = {...state.recentRecvSeqs, seq};
    final newHighest =
        seq > state.highestRecvSeq ? seq : state.highestRecvSeq;
    // Prune to bounded window so the set does not grow unbounded.
    final pruned = newSeqs.where((s) => s >= newHighest - seqWindow).toSet();

    final newPsids = psidIsFirstMessage
        ? {...state.peerSeenPsids, psid}
        : state.peerSeenPsids;

    final advanced = state.copyWith(
      highestRecvSeq: newHighest,
      recentRecvSeqs: pruned,
      peerSeenPsids: newPsids,
    );
    return ValidationResult._accept(advanced);
  }
}

class ValidationResult {
  /// The state to persist on accept; null when rejected.
  final RatchetState? state;

  /// Reason code when rejected; null on accept.
  final String? rejectReason;

  const ValidationResult._({this.state, this.rejectReason});

  factory ValidationResult._accept(RatchetState state) =>
      ValidationResult._(state: state);
  factory ValidationResult._reject(String reason) =>
      ValidationResult._(rejectReason: reason);
}
