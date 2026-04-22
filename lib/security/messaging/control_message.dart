import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Secure control message model for ACKs, deletes, and status updates.
///
/// Every control message is:
/// - Signed with HMAC-SHA256 (bound to session)
/// - Counter-protected against replay attacks
/// - Validated for sender identity
class ControlMessage {
  final String type;        // 'delivered', 'read', 'delete'
  final String chatId;
  final String messageId;
  final String senderId;
  final int timestamp;
  final int counter;        // Monotonic counter per chat for replay prevention
  final String signature;   // HMAC-SHA256 signature

  const ControlMessage({
    required this.type,
    required this.chatId,
    required this.messageId,
    required this.senderId,
    required this.timestamp,
    required this.counter,
    required this.signature,
  });

  /// Create and sign a control message.
  static Future<ControlMessage> create({
    required String type,
    required String chatId,
    required String messageId,
    required String senderId,
    required int counter,
    required Uint8List signingKey,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payload = _buildPayload(type, chatId, messageId, senderId, timestamp, counter);
    final signature = await _sign(payload, signingKey);

    return ControlMessage(
      type: type,
      chatId: chatId,
      messageId: messageId,
      senderId: senderId,
      timestamp: timestamp,
      counter: counter,
      signature: signature,
    );
  }

  /// Verify the control message signature and integrity.
  Future<bool> verify(Uint8List signingKey) async {
    final payload = _buildPayload(type, chatId, messageId, senderId, timestamp, counter);
    final expected = await _sign(payload, signingKey);

    // Constant-time comparison
    if (signature.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < signature.length; i++) {
      diff |= signature.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Validate the control message against known state.
  ///
  /// Returns null if valid, or an error string if invalid.
  String? validate({
    required String expectedSenderId,
    required int lastSeenCounter,
    int maxAgeMs = 300000, // 5 minutes
  }) {
    // Sender must match — no details in error (prevents enumeration)
    if (senderId != expectedSenderId) {
      return 'sender_mismatch';
    }

    // Counter must be strictly greater than last seen (replay prevention)
    if (counter <= lastSeenCounter) {
      return 'replay_detected';
    }

    // Timestamp must not be too old
    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (age > maxAgeMs) {
      return 'message_expired';
    }

    // Timestamp must not be in the future (clock skew tolerance: 30s)
    if (age < -30000) {
      return 'future_timestamp';
    }

    return null; // Valid
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'chatId': chatId,
        'mid': messageId,
        'sid': senderId,
        'ts': timestamp,
        'ctr': counter,
        'sig': signature,
      };

  /// Deserialize a control message. Throws [FormatException] if any
  /// security-critical field is missing — fail-closed, no defaults.
  factory ControlMessage.fromMap(Map<String, dynamic> map) {
    final type = map['type'] as String?;
    final chatId = map['chatId'] as String?;
    final messageId = map['mid'] as String?;
    final senderId = map['sid'] as String?;
    final timestamp = map['ts'] as int?;
    final counter = map['ctr'] as int?;
    final signature = map['sig'] as String?;

    if (type == null || chatId == null || messageId == null ||
        senderId == null || timestamp == null || counter == null ||
        signature == null || signature.isEmpty) {
      throw const FormatException('Malformed control message: missing required fields');
    }

    return ControlMessage(
      type: type,
      chatId: chatId,
      messageId: messageId,
      senderId: senderId,
      timestamp: timestamp,
      counter: counter,
      signature: signature,
    );
  }

  // ─── Signing Helpers ─────────────────────────────────────────────────────

  static String _buildPayload(
    String type, String chatId, String messageId,
    String senderId, int timestamp, int counter,
  ) {
    return '$type|$chatId|$messageId|$senderId|$timestamp|$counter';
  }

  static Future<String> _sign(String payload, Uint8List key) async {
    final hmac = Hmac.sha256();
    final mac = await hmac.calculateMac(
      utf8.encode(payload),
      secretKey: SecretKey(key),
    );
    return base64Encode(mac.bytes);
  }
}

/// Tracks the last control message counter per chat for replay prevention.
///
/// Counters are persisted to [EncryptedLocalStore] so that replay protection
/// survives app restarts. Without persistence, an attacker could replay old
/// ACK/control messages after a fresh app launch.
class ControlMessageCounter {
  final Map<String, int> _counters = {};
  final Map<String, int> _lastSeen = {};

  /// Callback invoked after counter state changes, allowing the owner
  /// to persist without tight coupling to EncryptedLocalStore.
  void Function(Map<String, dynamic> state)? onStateChanged;

  /// Get the next counter value for sending.
  int nextCounter(String chatId) {
    final current = _counters[chatId] ?? 0;
    _counters[chatId] = current + 1;
    _notifyStateChanged();
    return current + 1;
  }

  /// Record a received counter value. Returns false if replay detected.
  bool recordReceived(String chatId, int counter) {
    final last = _lastSeen[chatId] ?? 0;
    if (counter <= last) return false; // Replay
    _lastSeen[chatId] = counter;
    _notifyStateChanged();
    return true;
  }

  int getLastSeen(String chatId) => _lastSeen[chatId] ?? 0;

  Map<String, dynamic> toMap() => {
        'counters': Map<String, int>.from(_counters),
        'lastSeen': Map<String, int>.from(_lastSeen),
      };

  void loadFromMap(Map<String, dynamic> map) {
    final counters = map['counters'] as Map<String, dynamic>?;
    final lastSeen = map['lastSeen'] as Map<String, dynamic>?;
    if (counters != null) {
      _counters.addAll(counters.map((k, v) => MapEntry(k, v as int)));
    }
    if (lastSeen != null) {
      _lastSeen.addAll(lastSeen.map((k, v) => MapEntry(k, v as int)));
    }
  }

  void clear() {
    _counters.clear();
    _lastSeen.clear();
    _notifyStateChanged();
  }

  void _notifyStateChanged() {
    onStateChanged?.call(toMap());
  }
}
