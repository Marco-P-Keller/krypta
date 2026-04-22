import 'dart:async';
import 'dart:math';

/// Timing analysis protection for metadata operations.
///
/// Adds cryptographic jitter to network operations that could reveal
/// user behavior patterns through timing. Without jitter:
/// - ACK timing reveals exactly when a message was read
/// - Delivery ACK timing reveals when the app was opened
/// - Read receipt timing reveals user engagement patterns
///
/// With jitter, an observer sees operations spread across a random
/// window, making it infeasible to correlate with specific user actions.
class TimingProtection {
  static final _random = Random.secure();

  /// Minimum jitter delay for ACKs (milliseconds).
  static const minAckDelayMs = 500;

  /// Maximum jitter delay for ACKs (milliseconds).
  /// ACKs arrive 0.5–5 seconds after the actual event.
  static const maxAckDelayMs = 5000;

  /// Minimum jitter delay for read receipts (milliseconds).
  static const minReadDelayMs = 1000;

  /// Maximum jitter delay for read receipts (milliseconds).
  /// Read receipts arrive 1–10 seconds after the actual read.
  /// Longer window than delivery ACKs because read timing is more sensitive.
  static const maxReadDelayMs = 10000;

  /// Execute an action after a random delay within the specified range.
  ///
  /// The delay is generated using [Random.secure] to prevent predictability.
  /// Returns a [Timer] that can be cancelled if needed.
  static Timer delayedExecution(
    void Function() action, {
    required int minDelayMs,
    required int maxDelayMs,
  }) {
    final delayMs = minDelayMs + _random.nextInt(maxDelayMs - minDelayMs);
    return Timer(Duration(milliseconds: delayMs), action);
  }

  /// Send a delivery ACK with timing jitter.
  ///
  /// The ACK is delayed by 0.5–5 seconds to prevent an observer from
  /// correlating the ACK with the exact moment the message was received.
  static Timer sendDeliveryAckWithJitter(Future<void> Function() sendAck) {
    return delayedExecution(
      () => sendAck(),
      minDelayMs: minAckDelayMs,
      maxDelayMs: maxAckDelayMs,
    );
  }

  /// Send a read receipt with timing jitter.
  ///
  /// The receipt is delayed by 1–10 seconds. Longer window than delivery
  /// ACKs because "when was this read" is more privacy-sensitive than
  /// "when was this delivered" (the latter just means the app was open).
  static Timer sendReadReceiptWithJitter(Future<void> Function() sendReceipt) {
    return delayedExecution(
      () => sendReceipt(),
      minDelayMs: minReadDelayMs,
      maxDelayMs: maxReadDelayMs,
    );
  }

  /// Generate a random delay duration for general timing protection.
  static Duration randomDelay({
    required int minMs,
    required int maxMs,
  }) {
    return Duration(milliseconds: minMs + _random.nextInt(maxMs - minMs));
  }
}
