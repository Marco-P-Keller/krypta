import 'package:equatable/equatable.dart';

enum MessageStatus { sending, sent, delivered, read, failed }

class Message extends Equatable {
  final String id;
  final String chatId;
  final String senderId;
  final String recipientId;
  final String encryptedContent;
  final String? decryptedContent;
  final DateTime timestamp;
  final MessageStatus status;
  final Duration? selfDestructDuration;
  final DateTime? readAt;
  final bool burnAfterRead;

  /// When true, `decryptedContent` holds the password-encrypted blob.
  /// The actual plaintext is only revealed after the recipient enters
  /// the correct password. Once unlocked, `passwordUnlocked` becomes true
  /// and `decryptedContent` is replaced with the real plaintext.
  final bool isPasswordProtected;
  final bool passwordUnlocked;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.recipientId,
    required this.encryptedContent,
    this.decryptedContent,
    required this.timestamp,
    this.status = MessageStatus.sending,
    this.selfDestructDuration,
    this.readAt,
    this.burnAfterRead = false,
    this.isPasswordProtected = false,
    this.passwordUnlocked = false,
  });

  bool get isExpired {
    if (selfDestructDuration == null) return false;
    if (readAt == null) return false;
    return DateTime.now().isAfter(readAt!.add(selfDestructDuration!));
  }

  bool get shouldBurn => burnAfterRead && readAt != null;

  /// True when the message is locked and the recipient hasn't entered the password yet.
  bool get isLocked => isPasswordProtected && !passwordUnlocked;

  Message copyWith({
    Object? decryptedContent = _sentinel,
    MessageStatus? status,
    DateTime? readAt,
    bool? passwordUnlocked,
  }) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      recipientId: recipientId,
      encryptedContent: encryptedContent,
      decryptedContent: decryptedContent == _sentinel
          ? this.decryptedContent
          : decryptedContent as String?,
      timestamp: timestamp,
      status: status ?? this.status,
      selfDestructDuration: selfDestructDuration,
      readAt: readAt ?? this.readAt,
      burnAfterRead: burnAfterRead,
      isPasswordProtected: isPasswordProtected,
      passwordUnlocked: passwordUnlocked ?? this.passwordUnlocked,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'recipientId': recipientId,
        'encryptedContent': encryptedContent,
        // decryptedContent is NEVER persisted to disk.
        // Plaintext exists only in RAM for UI display and is cleared
        // on chat switch, memory scrub, or app restart.
        'timestamp': timestamp.millisecondsSinceEpoch,
        'status': status.index,
        'selfDestructMs': selfDestructDuration?.inMilliseconds,
        'readAt': readAt?.millisecondsSinceEpoch,
        'burnAfterRead': burnAfterRead ? 1 : 0,
        'pwProtected': isPasswordProtected ? 1 : 0,
        'pwUnlocked': passwordUnlocked ? 1 : 0,
      };

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      chatId: map['chatId'] as String,
      senderId: map['senderId'] as String,
      recipientId: map['recipientId'] as String,
      encryptedContent: map['encryptedContent'] as String,
      // decryptedContent never loaded from disk — RAM-only field.
      // After app restart, messages appear without content (maximum security).
      // Password-protected messages can be re-unlocked from encryptedContent.
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      status: MessageStatus.values[map['status'] as int],
      // A2: clamp stored milliseconds — non-positive → no self-destruct,
      // cap at 30 days to prevent Duration overflow in downstream timers.
      selfDestructDuration: _decodeSelfDestruct(map['selfDestructMs']),
      readAt: map['readAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['readAt'] as int)
          : null,
      burnAfterRead: (map['burnAfterRead'] as int?) == 1,
      isPasswordProtected: (map['pwProtected'] as int?) == 1,
      passwordUnlocked: (map['pwUnlocked'] as int?) == 1,
    );
  }

  @override
  List<Object?> get props => [id, chatId, senderId, timestamp, status];

  /// A2: safe decode for stored self-destruct milliseconds.
  /// Non-positive → null; capped at 30 days.
  static Duration? _decodeSelfDestruct(Object? raw) {
    if (raw is! int) return null;
    if (raw <= 0) return null;
    const maxMs = 30 * 24 * 60 * 60 * 1000;
    return Duration(milliseconds: raw > maxMs ? maxMs : raw);
  }
}

const _sentinel = Object();
