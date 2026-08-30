import 'package:equatable/equatable.dart';

class Chat extends Equatable {
  final String id;
  final String recipientId;
  final String recipientName;
  /// Kein `lastMessagePreview` mehr. Der Klartext der letzten Nachricht stand
  /// hier — und damit ein zweites Mal auf der Platte, in `chats.enc`, neben
  /// dem Nachrichtenspeicher. Angezeigt wurde er in der Chatliste, der einen
  /// Ansicht, die jemand ohne Oeffnen eines Chats zu sehen bekommt. Beides
  /// ist weg; was noetig ist, sagt `unreadCount`.
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isTyping;
  final Duration? defaultSelfDestruct;

  const Chat({
    required this.id,
    required this.recipientId,
    required this.recipientName,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isTyping = false,
    this.defaultSelfDestruct,
  });

  Chat copyWith({
    String? recipientName,
    Object? lastMessageTime = _sentinel,
    int? unreadCount,
    bool? isTyping,
    Object? defaultSelfDestruct = _sentinel,
  }) {
    return Chat(
      id: id,
      recipientId: recipientId,
      recipientName: recipientName ?? this.recipientName,
      lastMessageTime: lastMessageTime == _sentinel
          ? this.lastMessageTime
          : lastMessageTime as DateTime?,
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
        'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
        'unreadCount': unreadCount,
        'defaultSelfDestructMs': defaultSelfDestruct?.inMilliseconds,
      };

  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      id: map['id'] as String,
      recipientId: map['recipientId'] as String,
      recipientName: map['recipientName'] as String,
      // `lastMessagePreview` aus dem Bestand wird bewusst nicht gelesen. Beim
      // naechsten Schreiben faellt es damit aus der Datei.
      lastMessageTime: map['lastMessageTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'] as int)
          : null,
      unreadCount: (map['unreadCount'] as int?) ?? 0,
      // A2: clamp persisted self-destruct values so corrupted / migrated
      // state cannot reintroduce negative or overlong durations.
      defaultSelfDestruct: _decodeSelfDestruct(map['defaultSelfDestructMs']),
    );
  }

  /// A2: safe decode for stored self-destruct milliseconds.
  /// Non-positive → null (treated as "no self-destruct").
  /// Capped at 30 days to avoid integer overflow in downstream timers.
  static Duration? _decodeSelfDestruct(Object? raw) {
    if (raw is! int) return null;
    if (raw <= 0) return null;
    const maxMs = 30 * 24 * 60 * 60 * 1000;
    return Duration(milliseconds: raw > maxMs ? maxMs : raw);
  }

  @override
  List<Object?> get props => [id, recipientId];
}

const _sentinel = Object();
