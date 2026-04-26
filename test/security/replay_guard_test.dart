import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/ratchet/ratchet_state.dart';
import 'package:kryptaapp/security/ratchet/replay_guard.dart';

// C4+C5 regression tests — receive-side enforcement of sequence number (_seq)
// replay protection and anti-rollback session chain (_psid).
//
// Pure function tests so they cover the protocol logic independently of the
// messenger_provider wiring.

void main() {
  RatchetState makeState({
    int highestRecvSeq = -1,
    Set<int> recentRecvSeqs = const {},
    Set<String> peerSeenPsids = const {},
  }) {
    return RatchetState(
      rootKey: Uint8List(32),
      dhSendingPublic: Uint8List(32),
      dhSendingPrivate: Uint8List(32),
      highestRecvSeq: highestRecvSeq,
      recentRecvSeqs: recentRecvSeqs,
      peerSeenPsids: peerSeenPsids,
    );
  }

  group('ReplayGuard — C4 _seq replay window', () {
    test('fresh seq from empty state is accepted and state advances', () {
      final state = makeState();
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 0, '_sid': 'u1'},
        version: 3,
      );

      expect(result.rejectReason, isNull);
      expect(result.state!.highestRecvSeq, 0);
      expect(result.state!.recentRecvSeqs, equals({0}));
    });

    test('gap in seq is accepted (dropped messages tolerated)', () {
      final state = makeState(highestRecvSeq: 3, recentRecvSeqs: {3});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 7, '_sid': 'u1'},
        version: 3,
      );

      expect(result.rejectReason, isNull);
      expect(result.state!.highestRecvSeq, 7);
    });

    test('out-of-order seq within window is accepted (reorder-tolerant)', () {
      final state = makeState(highestRecvSeq: 10, recentRecvSeqs: {10});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 8, '_sid': 'u1'},
        version: 3,
      );

      expect(result.rejectReason, isNull,
          reason: 'seq 8 is within 200-window below highest=10 — accept');
      expect(result.state!.highestRecvSeq, 10,
          reason: 'out-of-order message does not lower highest');
      expect(result.state!.recentRecvSeqs, containsAll([10, 8]));
    });

    test('duplicate seq within window is rejected as REPLAY_SEQ', () {
      final state = makeState(highestRecvSeq: 4, recentRecvSeqs: {4});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 4, '_sid': 'u1'},
        version: 3,
      );

      expect(result.rejectReason, ReplayGuard.replaySeq);
      expect(result.state, isNull);
    });

    test('seq older than window is rejected as SEQ_TOO_OLD', () {
      final state = makeState(highestRecvSeq: 500, recentRecvSeqs: {500});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 100, '_sid': 'u1'}, // 500 - 100 = 400 > window
        version: 3,
      );

      expect(result.rejectReason, ReplayGuard.seqTooOld);
      expect(result.state, isNull);
    });

    test('seq window is pruned so the set does not grow unbounded', () {
      final state = makeState(highestRecvSeq: 200, recentRecvSeqs: {200, 0});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 300, '_sid': 'u1'},
        version: 3,
      );

      expect(result.rejectReason, isNull);
      expect(result.state!.recentRecvSeqs.contains(0), isFalse,
          reason: 'seq 0 is > 200 below new highest=300 — pruned');
      expect(result.state!.recentRecvSeqs.contains(300), isTrue);
    });

    test('missing _seq on v3 passes through (legacy-sender compat)', () {
      // Older clients still tag payloads as v3 but do not include _seq.
      // Rejecting them would break delivery during cross-version rollout.
      // The ratchet's AEAD still authenticates the payload; only the
      // additional replay layer is skipped for legacy senders.
      final state = makeState(highestRecvSeq: 4, recentRecvSeqs: {4});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_sid': 'u1'},
        version: 3,
      );

      expect(result.rejectReason, isNull);
      expect(result.state, same(state));
    });

    test('v2 legacy messages bypass seq enforcement', () {
      final state = makeState(highestRecvSeq: 4, recentRecvSeqs: {4});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'sid': 'u1'},
        version: 2,
      );

      expect(result.rejectReason, isNull);
      expect(result.state, same(state),
          reason: 'v2 passthrough — state unchanged');
    });
  });

  group('ReplayGuard — C5 _psid anti-rollback', () {
    test('new _psid on first message (_seq == 0) is accepted and recorded', () {
      final state = makeState();
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 0, '_sid': 'u1', '_psid': 'session-abc'},
        version: 3,
      );

      expect(result.rejectReason, isNull);
      expect(result.state!.peerSeenPsids, contains('session-abc'));
    });

    test('previously-seen _psid on first message is rejected as rollback', () {
      final state = makeState(peerSeenPsids: {'session-abc'});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 0, '_sid': 'u1', '_psid': 'session-abc'},
        version: 3,
      );

      expect(result.rejectReason, ReplayGuard.rollbackPsid);
      expect(result.state, isNull);
    });

    test('_psid on non-first message (_seq > 0) is ignored, not recorded', () {
      final state = makeState(highestRecvSeq: 4, recentRecvSeqs: {4});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 5, '_sid': 'u1', '_psid': 'session-xyz'},
        version: 3,
      );

      expect(result.rejectReason, isNull);
      expect(result.state!.peerSeenPsids.contains('session-xyz'), isFalse,
          reason: '_psid only honored when _seq == 0');
    });

    test('message without _psid is accepted (normal message)', () {
      final state = makeState(peerSeenPsids: {'session-abc'});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 0, '_sid': 'u1'},
        version: 3,
      );

      expect(result.rejectReason, isNull);
      expect(result.state!.peerSeenPsids, equals({'session-abc'}),
          reason: 'no _psid means no change to seen set');
    });

    test('accepted _psid extends existing seen set, does not replace it', () {
      final state = makeState(peerSeenPsids: {'s1', 's2'});
      final result = ReplayGuard.validate(
        state: state,
        innerPayload: {'_seq': 0, '_sid': 'u1', '_psid': 's3'},
        version: 3,
      );

      expect(result.rejectReason, isNull);
      expect(result.state!.peerSeenPsids, equals({'s1', 's2', 's3'}));
    });
  });
}
