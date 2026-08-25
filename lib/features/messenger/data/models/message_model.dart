import 'package:equatable/equatable.dart';

enum MessageStatus { sending, sent, delivered, read, failed }

/// Ein Ereignis, das als Systemeintrag im Verlauf steht — keine Nachricht,
/// sondern ein Hinweis.
///
/// Der Screenshot-Schutz wurde entfernt: er beruhte auf undokumentiertem
/// Verhalten und wirkte auf iOS 26.6 nicht mehr. Screenshots lassen sich auf
/// iOS ohnehin nicht verhindern. Statt einen Schutz zu behaupten, den es nicht
/// gibt, sagt die App jetzt beiden Seiten Bescheid.
enum SystemEventKind {
  /// Jemand hat einen Screenshot des Chats gemacht.
  screenshot,

  /// Jemand nimmt den Bildschirm auf oder spiegelt ihn.
  screenRecording,
}

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

  /// Gesetzt, wenn dieser Eintrag ein Hinweis ist und keine Nachricht.
  ///
  /// Bewusst nur die **Art** des Ereignisses, kein Text: `decryptedContent`
  /// wird nie gespeichert, und ein festgeschriebener deutscher Satz bliebe
  /// nach einem Sprachwechsel deutsch. Der Text entsteht deshalb erst beim
  /// Anzeigen. Wer es ausgelöst hat, steht in [senderId].
  final SystemEventKind? systemEvent;

  bool get isSystemEvent => systemEvent != null;

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
    this.systemEvent,
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
      // Nicht vergessen: ohne diese Zeile wird aus einem Systemhinweis eine
      // gewoehnliche Nachricht ohne Inhalt, und die Blase zeigt „••••••".
      // Genau das passierte der Gegenseite, sobald der Provider beim
      // Verlassen des Chats den Klartext ausraeumte.
      systemEvent: systemEvent,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'recipientId': recipientId,
        'encryptedContent': encryptedContent,
        // Der Klartext wird mitgeschrieben — sonst zeigt der Verlauf nach
        // dem Schliessen der App nur noch „••••••", und ein Messenger, der
        // seine eigene Geschichte vergisst, ist keiner.
        //
        // Der Schutz liegt nicht im Wegwerfen, sondern im Ort: der
        // EncryptedLocalStore verschluesselt mit XChaCha20-Poly1305 unter
        // einem Schluessel aus dem Schluesselbund, nach Moeglichkeit in der
        // Secure Enclave verpackt und erst nach der ersten Entsperrung des
        // Geraets lesbar. Denselben Schluessel haelt die App ohnehin im
        // Arbeitsspeicher.
        //
        // Ausgenommen: der Klartext einer passwortgeschuetzten Nachricht.
        // Der gehoert hinter das Passwort. Solange sie gesperrt ist, steht
        // hier ohnehin nur der verschluesselte Block — der bleibt, sonst
        // liesse sie sich nach einem Neustart nie wieder oeffnen.
        if (!(isPasswordProtected && passwordUnlocked) &&
            decryptedContent != null)
          'decryptedContent': decryptedContent,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'status': status.index,
        'selfDestructMs': selfDestructDuration?.inMilliseconds,
        'readAt': readAt?.millisecondsSinceEpoch,
        'burnAfterRead': burnAfterRead ? 1 : 0,
        'pwProtected': isPasswordProtected ? 1 : 0,
        'pwUnlocked': passwordUnlocked ? 1 : 0,
        if (systemEvent != null) 'sysEvent': systemEvent!.index,
      };

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      chatId: map['chatId'] as String,
      senderId: map['senderId'] as String,
      recipientId: map['recipientId'] as String,
      encryptedContent: map['encryptedContent'] as String,
      decryptedContent: map['decryptedContent'] as String?,
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
      // Fehlt das Feld, stammt der Eintrag aus der Zeit vor den
      // Systemhinweisen — dann ist es eine gewöhnliche Nachricht.
      systemEvent: map['sysEvent'] != null
          ? SystemEventKind.values[map['sysEvent'] as int]
          : null,
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
