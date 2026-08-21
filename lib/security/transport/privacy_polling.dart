import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Privacy-preserving polling as an alternative to push notifications.
///
/// When push privacy mode is enabled, the app stops using Firebase Cloud
/// Messaging (FCM) and Firestore real-time listeners, and instead polls
/// for new messages at randomized intervals. This prevents:
///
/// 1. **Push provider metadata**: Google/Apple cannot learn when messages
///    arrive or their frequency — no FCM tokens are registered.
/// 2. **Timing correlation**: Randomized jitter on poll intervals prevents
///    a network observer from correlating poll timing with message delivery.
/// 3. **Connection fingerprinting**: Firestore long-polling/WebSocket
///    connections reveal when a user is online. Periodic polls are less
///    distinguishable from other HTTPS traffic.
///
/// All control messages (ACKs, deletes, read receipts) now travel through
/// the encrypted message channel — no separate ACK polling needed.
///
/// Trade-off: Higher latency (messages arrive on next poll, not instantly).
/// Typical delivery time: 5-30 seconds depending on jitter.
class PrivacyPolling {
  final FirebaseFirestore _db;
  final Random _random = Random.secure();

  Timer? _messageTimer;
  bool _isRunning = false;

  /// Base interval between polls (before jitter).
  static const baseInterval = Duration(seconds: 10);

  /// Maximum random jitter added to each poll interval.
  /// Actual interval = baseInterval + random(0, maxJitter).
  static const maxJitter = Duration(seconds: 20);

  /// Callback invoked when new messages are found during a poll.
  /// Control messages (ACKs, deletes) arrive through the same channel.
  final void Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>)? onMessages;

  PrivacyPolling({
    FirebaseFirestore? db,
    this.onMessages,
  }) : _db = db ?? FirebaseFirestore.instance;

  /// Start polling for messages with randomized intervals.
  void start(String userId) {
    if (_isRunning) return;
    _isRunning = true;

    // Stagger initial poll to avoid synchronized network activity
    _scheduleNextMessagePoll(userId, initialDelay: true);
  }

  /// Stop all polling timers.
  void stop() {
    _messageTimer?.cancel();
    _messageTimer = null;
    _isRunning = false;
  }

  /// Calculate the next poll interval with cryptographic jitter.
  Duration _nextInterval({bool initialDelay = false}) {
    final jitterMs = _random.nextInt(maxJitter.inMilliseconds);
    final base = initialDelay
        ? Duration(milliseconds: _random.nextInt(baseInterval.inMilliseconds))
        : baseInterval;
    return base + Duration(milliseconds: jitterMs);
  }

  void _scheduleNextMessagePoll(String userId, {bool initialDelay = false}) {
    _messageTimer?.cancel();
    if (!_isRunning) return;

    final interval = _nextInterval(initialDelay: initialDelay);
    _messageTimer = Timer(interval, () async {
      await _pollMessages(userId);
      _scheduleNextMessagePoll(userId);
    });
  }

  Future<void> _pollMessages(String userId) async {
    try {
      final snapshot = await _db
          .collection('messages')
          .doc(userId)
          .collection('inbox')
          .orderBy('ts', descending: false)
          .get();

      if (snapshot.docs.isNotEmpty) {
        onMessages?.call(snapshot.docs);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Privacy poll (messages) failed: $e');
    }
  }
}
