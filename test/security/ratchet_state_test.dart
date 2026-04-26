import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/ratchet/ratchet_state.dart';

void main() {
  group('RatchetState', () {
    RatchetState _createState({
      int? protocolVersion,
      String? sessionId,
      String? previousSessionId,
      DateTime? createdAt,
      int globalSendSeqNo = 0,
      int highestRecvSeq = -1,
    }) {
      return RatchetState(
        protocolVersion: protocolVersion ?? RatchetState.currentProtocolVersion,
        rootKey: Uint8List(32),
        dhSendingPublic: Uint8List(32),
        dhSendingPrivate: Uint8List(32),
        sessionId: sessionId,
        previousSessionId: previousSessionId,
        createdAt: createdAt,
        globalSendSeqNo: globalSendSeqNo,
        highestRecvSeq: highestRecvSeq,
      );
    }

    test('current protocol version is 1', () {
      expect(RatchetState.currentProtocolVersion, 1);
    });

    test('serialization roundtrip preserves all new fields', () {
      final now = DateTime.now();
      final state = _createState(
        protocolVersion: 1,
        sessionId: 'test-session-123',
        previousSessionId: 'old-session-456',
        createdAt: now,
        globalSendSeqNo: 42,
        highestRecvSeq: 37,
      );

      final map = state.toMap();
      final restored = RatchetState.fromMap(map);

      expect(restored.protocolVersion, 1);
      expect(restored.sessionId, 'test-session-123');
      expect(restored.previousSessionId, 'old-session-456');
      expect(restored.createdAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch);
      expect(restored.globalSendSeqNo, 42);
      expect(restored.highestRecvSeq, 37);
    });

    test('backward compatibility: missing fields default correctly', () {
      // Simulate a v1 state without the new fields
      final oldMap = {
        'rk': base64Encode(Uint8List(32)),
        'dhsp': base64Encode(Uint8List(32)),
        'dhsk': base64Encode(Uint8List(32)),
      };

      final state = RatchetState.fromMap(oldMap);
      expect(state.protocolVersion, 1);
      expect(state.sessionId, isNull);
      expect(state.previousSessionId, isNull);
      expect(state.globalSendSeqNo, 0);
      // Back-compat: older state used 'grn' as next-expected; map to hrs-1.
      expect(state.highestRecvSeq, -1);
    });

    test('copyWith preserves new fields', () {
      final state = _createState(
        sessionId: 'sid-1',
        globalSendSeqNo: 10,
      );

      final updated = state.copyWith(globalSendSeqNo: 11);
      expect(updated.sessionId, 'sid-1');
      expect(updated.globalSendSeqNo, 11);
    });

    test('copyWith can update sessionId', () {
      final state = _createState(sessionId: 'old');
      final updated = state.copyWith(sessionId: 'new');
      expect(updated.sessionId, 'new');
    });

    test('copyWith can set sessionId to null', () {
      final state = _createState(sessionId: 'has-value');
      final updated = state.copyWith(sessionId: null);
      expect(updated.sessionId, isNull);
    });

    test('toMap includes protocol version', () {
      final state = _createState();
      final map = state.toMap();
      expect(map['pv'], RatchetState.currentProtocolVersion);
    });

    test('toMap includes sequence numbers', () {
      final state = _createState(globalSendSeqNo: 5, highestRecvSeq: 3);
      final map = state.toMap();
      expect(map['gsn'], 5);
      expect(map['hrs'], 3);
    });
  });
}
