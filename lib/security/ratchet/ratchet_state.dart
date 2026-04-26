import 'dart:convert';
import 'dart:typed_data';

/// Immutable Double Ratchet session state for one chat.
///
/// Based on the Signal Double Ratchet spec:
/// https://signal.org/docs/specifications/doubleratchet/
class RatchetState {
  /// Protocol version — enables future algorithm upgrades.
  /// v1 = original (X25519 + HKDF-SHA256 + XChaCha20-Poly1305)
  static const currentProtocolVersion = 1;
  final int protocolVersion;

  final Uint8List rootKey;
  final Uint8List? sendingChainKey;
  final Uint8List? receivingChainKey;
  final Uint8List dhSendingPublic;
  final Uint8List dhSendingPrivate;
  final Uint8List? dhReceivingPublic;
  final int sendMessageNumber;
  final int receiveMessageNumber;
  final int previousChainLength;

  /// Map from "base64(dhPub):msgNum" → message key (32 bytes).
  /// Holds keys for out-of-order messages.
  final Map<String, Uint8List> skippedMessageKeys;

  /// Creation timestamps (ms since epoch) for skipped keys.
  /// Keys older than 30 days are pruned to preserve forward secrecy.
  final Map<String, int> skippedKeyTimestamps;

  /// Unique session identifier (UUID). Assigned at session creation.
  /// Used for anti-rollback protection — new sessions reference the previous.
  final String? sessionId;

  /// Session ID of the previous session. Included in the first message
  /// of a new session so the receiver can detect rollback attacks.
  final String? previousSessionId;

  /// When this session was created. Used for forced session rotation —
  /// sessions older than [AppConstants.sessionMaxAge] trigger re-handshake.
  final DateTime createdAt;

  /// Monotonic per-session send sequence number for replay protection.
  /// Incremented with every sent message, independent of ratchet chain counters.
  final int globalSendSeqNo;

  /// Highest per-session send-sequence number we've seen from the peer.
  /// Informational — the enforcement check uses [recentRecvSeqs] + the
  /// `ReplayGuard.seqWindow` width around this value to tolerate reorders
  /// within the Double Ratchet skip window.
  final int highestRecvSeq;

  /// Bounded sliding window of recently-seen `_seq` values (size capped by
  /// `ReplayGuard.seqWindow`). A seq already in this set is a replay; a seq
  /// far below `highestRecvSeq - seqWindow` is a stale replay past the
  /// window; otherwise the seq is fresh.
  final Set<int> recentRecvSeqs;

  /// Set of `_psid` values we've already observed from the peer. Every
  /// first-message-of-a-new-session carries the sender's previous session id;
  /// re-seeing a value here means someone is replaying an older handshake —
  /// reject to prevent session-rollback attacks.
  final Set<String> peerSeenPsids;

  RatchetState({
    this.protocolVersion = currentProtocolVersion,
    required this.rootKey,
    this.sendingChainKey,
    this.receivingChainKey,
    required this.dhSendingPublic,
    required this.dhSendingPrivate,
    this.dhReceivingPublic,
    this.sendMessageNumber = 0,
    this.receiveMessageNumber = 0,
    this.previousChainLength = 0,
    Map<String, Uint8List>? skippedMessageKeys,
    Map<String, int>? skippedKeyTimestamps,
    this.sessionId,
    this.previousSessionId,
    DateTime? createdAt,
    this.globalSendSeqNo = 0,
    this.highestRecvSeq = -1,
    Set<int>? recentRecvSeqs,
    Set<String>? peerSeenPsids,
  }) : skippedMessageKeys = skippedMessageKeys ?? const {},
       skippedKeyTimestamps = skippedKeyTimestamps ?? const {},
       recentRecvSeqs = recentRecvSeqs ?? const <int>{},
       peerSeenPsids = peerSeenPsids ?? const <String>{},
       createdAt = createdAt ?? DateTime.now();

  RatchetState copyWith({
    int? protocolVersion,
    Uint8List? rootKey,
    Object? sendingChainKey = _absent,
    Object? receivingChainKey = _absent,
    Uint8List? dhSendingPublic,
    Uint8List? dhSendingPrivate,
    Object? dhReceivingPublic = _absent,
    int? sendMessageNumber,
    int? receiveMessageNumber,
    int? previousChainLength,
    Map<String, Uint8List>? skippedMessageKeys,
    Map<String, int>? skippedKeyTimestamps,
    Object? sessionId = _absent,
    Object? previousSessionId = _absent,
    DateTime? createdAt,
    int? globalSendSeqNo,
    int? highestRecvSeq,
    Set<int>? recentRecvSeqs,
    Set<String>? peerSeenPsids,
  }) {
    return RatchetState(
      protocolVersion: protocolVersion ?? this.protocolVersion,
      rootKey: rootKey ?? this.rootKey,
      sendingChainKey: sendingChainKey == _absent
          ? this.sendingChainKey
          : sendingChainKey as Uint8List?,
      receivingChainKey: receivingChainKey == _absent
          ? this.receivingChainKey
          : receivingChainKey as Uint8List?,
      dhSendingPublic: dhSendingPublic ?? this.dhSendingPublic,
      dhSendingPrivate: dhSendingPrivate ?? this.dhSendingPrivate,
      dhReceivingPublic: dhReceivingPublic == _absent
          ? this.dhReceivingPublic
          : dhReceivingPublic as Uint8List?,
      sendMessageNumber: sendMessageNumber ?? this.sendMessageNumber,
      receiveMessageNumber: receiveMessageNumber ?? this.receiveMessageNumber,
      previousChainLength: previousChainLength ?? this.previousChainLength,
      skippedMessageKeys: skippedMessageKeys ?? this.skippedMessageKeys,
      skippedKeyTimestamps: skippedKeyTimestamps ?? this.skippedKeyTimestamps,
      sessionId: sessionId == _absent
          ? this.sessionId
          : sessionId as String?,
      previousSessionId: previousSessionId == _absent
          ? this.previousSessionId
          : previousSessionId as String?,
      createdAt: createdAt ?? this.createdAt,
      globalSendSeqNo: globalSendSeqNo ?? this.globalSendSeqNo,
      highestRecvSeq: highestRecvSeq ?? this.highestRecvSeq,
      recentRecvSeqs: recentRecvSeqs ?? this.recentRecvSeqs,
      peerSeenPsids: peerSeenPsids ?? this.peerSeenPsids,
    );
  }

  Map<String, dynamic> toMap() => {
        'pv': protocolVersion,
        'rk': base64Encode(rootKey),
        'cks': sendingChainKey != null ? base64Encode(sendingChainKey!) : null,
        'ckr': receivingChainKey != null ? base64Encode(receivingChainKey!) : null,
        'dhsp': base64Encode(dhSendingPublic),
        'dhsk': base64Encode(dhSendingPrivate),
        'dhrp': dhReceivingPublic != null ? base64Encode(dhReceivingPublic!) : null,
        'ns': sendMessageNumber,
        'nr': receiveMessageNumber,
        'pn': previousChainLength,
        'skip': skippedMessageKeys.map((k, v) => MapEntry(k, base64Encode(v))),
        if (skippedKeyTimestamps.isNotEmpty)
          'skipTs': skippedKeyTimestamps,
        if (sessionId != null) 'sid': sessionId,
        if (previousSessionId != null) 'psid': previousSessionId,
        'ca': createdAt.millisecondsSinceEpoch,
        'gsn': globalSendSeqNo,
        'hrs': highestRecvSeq,
        if (recentRecvSeqs.isNotEmpty) 'rrs': recentRecvSeqs.toList(),
        if (peerSeenPsids.isNotEmpty) 'psp': peerSeenPsids.toList(),
      };

  factory RatchetState.fromMap(Map<String, dynamic> map) {
    final skipRaw = (map['skip'] as Map<String, dynamic>?) ?? {};
    final skipTsRaw = (map['skipTs'] as Map<String, dynamic>?) ?? {};
    return RatchetState(
      protocolVersion: (map['pv'] as int?) ?? 1,
      rootKey: base64Decode(map['rk'] as String),
      sendingChainKey:
          map['cks'] != null ? base64Decode(map['cks'] as String) : null,
      receivingChainKey:
          map['ckr'] != null ? base64Decode(map['ckr'] as String) : null,
      dhSendingPublic: base64Decode(map['dhsp'] as String),
      dhSendingPrivate: base64Decode(map['dhsk'] as String),
      dhReceivingPublic:
          map['dhrp'] != null ? base64Decode(map['dhrp'] as String) : null,
      sendMessageNumber: (map['ns'] as int?) ?? 0,
      receiveMessageNumber: (map['nr'] as int?) ?? 0,
      previousChainLength: (map['pn'] as int?) ?? 0,
      skippedMessageKeys: skipRaw.map((k, v) => MapEntry(k, base64Decode(v as String))),
      skippedKeyTimestamps: skipTsRaw.map((k, v) => MapEntry(k, v as int)),
      sessionId: map['sid'] as String?,
      previousSessionId: map['psid'] as String?,
      createdAt: map['ca'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['ca'] as int)
          : null,
      globalSendSeqNo: (map['gsn'] as int?) ?? 0,
      // Back-compat: older persisted state used 'grn' as next-expected seq —
      // translate to highestRecvSeq = grn - 1. To avoid a one-time replay
      // window across the upgrade boundary (seqs in [grn-200 .. grn-1] were
      // accepted before but wouldn't be remembered here), seed the window
      // conservatively with that whole range.
      highestRecvSeq: (map['hrs'] as int?) ??
          (((map['grn'] as int?) ?? 0) - 1),
      recentRecvSeqs: (map['rrs'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toSet() ??
          _seedLegacyRecvWindow(map['grn'] as int?),
      peerSeenPsids: (map['psp'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          const <String>{},
    );
  }
}

const _absent = Object();

/// Build a conservative seen-seq window from a legacy `grn` value, so any seq
/// the peer could have sent before the upgrade cannot be replayed as fresh
/// after the upgrade. Returns an empty set if there is no legacy value.
Set<int> _seedLegacyRecvWindow(int? grn) {
  if (grn == null || grn <= 0) return const <int>{};
  // grn was "next-expected", so values [0 .. grn-1] were already accepted.
  // Cap at the ReplayGuard window size to keep the set bounded.
  const windowSize = 200;
  final lowest = grn - windowSize < 0 ? 0 : grn - windowSize;
  return {for (var s = lowest; s < grn; s++) s};
}
