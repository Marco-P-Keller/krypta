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

  /// Wie viele Systemhinweise der Gegenseite noch ungesehen sind.
  ///
  /// Screenshot, Bildschirmaufnahme, Fristwechsel, geloeschtes Konto. Die
  /// tauchten in der Chatliste vorher **gar nicht** auf: der Hinweis landete
  /// im Chat, aber der Eintrag rutschte nicht einmal nach oben. Man erfuhr
  /// davon nur, wenn man den Chat zufaellig oeffnete.
  ///
  /// Bewusst getrennt von [unreadCount] gehalten: ein Screenshot ist keine
  /// Nachricht, und „1 neu" darf nicht beides heissen koennen. Angezeigt wird
  /// darum ein Punkt statt einer Zahl — die genaue Menge sagt hier nichts.
  final int hinweisCount;

  /// Wann die erste noch ungelesene Nachricht kam.
  ///
  /// In der Chatliste stand die Uhrzeit der **letzten** Nachricht. Kamen
  /// mehrere neue herein, wanderte sie mit, und der Zeitpunkt, an dem etwas
  /// Neues anfing, war nicht mehr abzulesen. Solange etwas ungelesen ist,
  /// gehoert dort die erste davon hin — siehe [displayTime].
  ///
  /// `null` heisst: nichts ungelesen, oder ein Bestandsdatensatz von vor
  /// dieser Aenderung.
  final DateTime? firstUnreadAt;
  final bool isTyping;
  final Duration? defaultSelfDestruct;

  /// Wann [defaultSelfDestruct] eingeschaltet wurde.
  ///
  /// Der Chat-Timer gilt auch fuer das, was schon dasteht — aber erst ab
  /// dem Einschalten. Ohne diesen Zeitpunkt waere mit einem Tipp der halbe
  /// Verlauf im selben Moment weg.
  final DateTime? defaultSelfDestructSetAt;

  const Chat({
    required this.id,
    required this.recipientId,
    required this.recipientName,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.hinweisCount = 0,
    this.firstUnreadAt,
    this.isTyping = false,
    this.defaultSelfDestruct,
    this.defaultSelfDestructSetAt,
  });

  Chat copyWith({
    String? recipientName,
    Object? lastMessageTime = _sentinel,
    int? unreadCount,
    int? hinweisCount,
    Object? firstUnreadAt = _sentinel,
    bool? isTyping,
    Object? defaultSelfDestruct = _sentinel,
    Object? defaultSelfDestructSetAt = _sentinel,
  }) {
    return Chat(
      id: id,
      recipientId: recipientId,
      recipientName: recipientName ?? this.recipientName,
      lastMessageTime: lastMessageTime == _sentinel
          ? this.lastMessageTime
          : lastMessageTime as DateTime?,
      unreadCount: unreadCount ?? this.unreadCount,
      hinweisCount: hinweisCount ?? this.hinweisCount,
      firstUnreadAt: firstUnreadAt == _sentinel
          ? this.firstUnreadAt
          : firstUnreadAt as DateTime?,
      isTyping: isTyping ?? this.isTyping,
      defaultSelfDestruct: defaultSelfDestruct == _sentinel
          ? this.defaultSelfDestruct
          : defaultSelfDestruct as Duration?,
      defaultSelfDestructSetAt: defaultSelfDestructSetAt == _sentinel
          ? this.defaultSelfDestructSetAt
          : defaultSelfDestructSetAt as DateTime?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
        'unreadCount': unreadCount,
        'hinweisCount': hinweisCount,
        'firstUnreadAt': firstUnreadAt?.millisecondsSinceEpoch,
        'defaultSelfDestructMs': defaultSelfDestruct?.inMilliseconds,
        'defaultSelfDestructSetAt':
            defaultSelfDestructSetAt?.millisecondsSinceEpoch,
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
      // Bestandsdatensaetze kennen das Feld nicht: dann eben kein Punkt.
      hinweisCount: (map['hinweisCount'] as int?) ?? 0,
      firstUnreadAt: map['firstUnreadAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['firstUnreadAt'] as int)
          : null,
      // A2: clamp persisted self-destruct values so corrupted / migrated
      // state cannot reintroduce negative or overlong durations.
      defaultSelfDestruct: _decodeSelfDestruct(map['defaultSelfDestructMs']),
      defaultSelfDestructSetAt: map['defaultSelfDestructSetAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              map['defaultSelfDestructSetAt'] as int)
          : null,
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

  /// Die Uhrzeit, die in der Chatliste steht.
  ///
  /// Solange etwas ungelesen ist, bleibt sie bei der **ersten** neuen
  /// Nachricht stehen — auch wenn danach weitere hereinkommen. Sonst zeigt
  /// sie die letzte. Fehlt der Vermerk (Bestandsdatensatz), faellt sie auf
  /// die letzte zurueck: lieber die alte Uhrzeit als gar keine.
  ///
  /// Ein ungesehener Hinweis zaehlt hier mit: wer wissen will, seit wann
  /// etwas liegt, meint auch den Screenshot von heute morgen.
  DateTime? get displayTime => hatNeues
      ? (firstUnreadAt ?? lastMessageTime)
      : lastMessageTime;

  /// Ob in diesem Chat ueberhaupt etwas Ungesehenes liegt — Nachricht oder
  /// Hinweis. Was die Chatliste hervorhebt, haengt daran.
  bool get hatNeues => unreadCount > 0 || hinweisCount > 0;

  @override
  List<Object?> get props => [id, recipientId];
}

const _sentinel = Object();
