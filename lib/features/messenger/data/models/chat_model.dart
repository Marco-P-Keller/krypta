import 'package:equatable/equatable.dart';

class Chat extends Equatable {
  final String id;
  final String recipientId;
  final String recipientName;
  final String? lastMessagePreview;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isTyping;
  final Duration? defaultSelfDestruct;

  const Chat({
    required this.id,
    required this.recipientId,
    required this.recipientName,
    this.lastMessagePreview,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isTyping = false,
    this.defaultSelfDestruct,
  });

  Chat copyWith({
    String? recipientName,
    String? lastMessagePreview,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isTyping,
    // Use _sentinel pattern: pass Duration.zero to clear, null to keep
    Object? defaultSelfDestruct = _sentinel,
  }) {
    return Chat(
      id: id,
      recipientId: recipientId,
      recipientName: recipientName ?? this.recipientName,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isTyping: isTyping ?? this.isTyping,
      defaultSelfDestruct: defaultSelfDestruct == _sentinel
          ? this.defaultSelfDestruct
          : defaultSelfDestruct as Duration?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'lastMessagePreview': lastMessagePreview,
        'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
        'unreadCount': unreadCount,
        'defaultSelfDestructMs': defaultSelfDestruct?.inMilliseconds,
      };

  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      id: map['id'] as String,
      recipientId: map['recipientId'] as String,
      recipientName: map['recipientName'] as String,
      lastMessagePreview: map['lastMessagePreview'] as String?,
      lastMessageTime: map['lastMessageTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'] as int)
          : null,
      unreadCount: (map['unreadCount'] as int?) ?? 0,
      defaultSelfDestruct: map['defaultSelfDestructMs'] != null
          ? Duration(milliseconds: map['defaultSelfDestructMs'] as int)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, recipientId];
}

const _sentinel = Object();
