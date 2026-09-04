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

  /// Die Gegenseite hat die Notfall-Löschung ausgelöst. Das Konto gibt es
  /// nicht mehr — eine Nachricht dorthin käme nie an.
  accountDeleted,

  /// Die Löschdauer des Chats wurde geändert. Die neue Dauer steht am
  /// Hinweis selbst in `selfDestructDuration`; `null` heißt ausgeschaltet.
  selfDestructChanged,

  /// Der Chat steht jetzt auf „Direkt nach dem Lesen". Keine Dauer — was
  /// gelesen ist, geht beim Verlassen des Chats.
  selfDestructAfterRead,
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

  /// Ob [selfDestructDuration] vom **Chat-Timer** stammt.
  ///
  /// Beide Uhren starten bei der **Zustellung** (siehe [deliveredAt]). Der
  /// Unterschied liegt woanders: eine Chat-Frist folgt der **aktuellen**
  /// Einstellung des Chats, weil die beiden Seiten gehoert und zwischen ihnen
  /// abgeglichen wird. Eine eigene Frist der Nachricht behaelt sie.
  ///
  /// Die Frist reist in beiden Faellen mit, damit beide Seiten dieselbe
  /// kennen, auch wenn die Meldung ueber eine Aenderung noch unterwegs ist.
  ///
  /// `false` ist der sichere Vorgabewert: alles, was vor dieser
  /// Unterscheidung gespeichert wurde, war ein eigener Timer.
  final bool selfDestructFromChat;

  /// Wann diese Nachricht auf dem Geraet der Gegenseite angekommen ist.
  ///
  /// **Der Startpunkt jeder Loeschfrist**, und der einzige Zeitpunkt, den
  /// beide Geraete gleich lesen. [timestamp] taugt dafuer nicht: beim
  /// Absender ist er der Sendezeitpunkt, beim Empfaenger der des Abholens.
  /// Wartet eine Nachricht auf dem Server, lagen zwischen beiden Stunden —
  /// und die Fassung des Absenders lief entsprechend frueher ab.
  ///
  /// Der Empfaenger setzt ihn beim Abholen, der Absender uebernimmt ihn aus
  /// der Zustellbestaetigung. `null` heisst: noch nicht zugestellt, es laeuft
  /// keine Uhr. Bestandsdatensaetze bekommen ihn beim Laden nachgetragen,
  /// siehe SelfDestructPolicy.zustellungNachtragen.
  final DateTime? deliveredAt;

  final DateTime? readAt;
  final bool burnAfterRead;

  /// Ob diese Nachricht nur einmal geoeffnet werden darf.
  ///
  /// Ersetzt seit dem 02.09.2026 den Einzeltimer und Burn after read. Beim
  /// Empfaenger bleibt der Inhalt verborgen, bis er bestaetigt hat; mit dem
  /// Bestaetigen ist die Nachricht von der Platte fort. Siehe EinmaligPolicy.
  ///
  /// Kein Parameter in copyWith: der Wert steht beim Anlegen fest und aendert
  /// sich nie. Was sich aendert, ist ob die Nachricht noch da ist.
  final bool einmalig;

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
    this.deliveredAt,
    this.status = MessageStatus.sending,
    this.selfDestructDuration,
    this.selfDestructFromChat = false,
    this.readAt,
    this.burnAfterRead = false,
    this.einmalig = false,
    this.isPasswordProtected = false,
    this.passwordUnlocked = false,
    this.systemEvent,
  });

  /// Ob eine gelesene Nachricht mit `burnAfterRead` faellig ist.
  ///
  /// Bestand: aeltere Absender setzen das Feld noch. Die Regel des Chats
  /// („Direkt nach dem Lesen") liegt in SelfDestructPolicy.nachLesenFaellig.
  ///
  /// Ein `isExpired` gab es hier auch einmal. Es rechnete eine Chat-Frist ab
  /// `readAt` — eine Regel, die es seit dem 02.09.2026 nicht mehr gibt — und
  /// war damit eine zweite, abweichende Antwort auf dieselbe Frage. Wer
  /// wissen will, ob eine Nachricht faellig ist, fragt SelfDestructPolicy:
  /// die kennt beide Fristen und die Zustellung, und sie laesst sich pruefen.
  bool get shouldBurn => burnAfterRead && readAt != null;

  /// True when the message is locked and the recipient hasn't entered the password yet.
  bool get isLocked => isPasswordProtected && !passwordUnlocked;

  Message copyWith({
    Object? decryptedContent = _sentinel,
    MessageStatus? status,
    DateTime? deliveredAt,
    DateTime? readAt,
    bool? passwordUnlocked,
    bool? selfDestructFromChat,
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
      deliveredAt: deliveredAt ?? this.deliveredAt,
      status: status ?? this.status,
      selfDestructDuration: selfDestructDuration,
      selfDestructFromChat: selfDestructFromChat ?? this.selfDestructFromChat,
      readAt: readAt ?? this.readAt,
      burnAfterRead: burnAfterRead,
      einmalig: einmalig,
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
        'deliveredAt': deliveredAt?.millisecondsSinceEpoch,
        'status': status.index,
        'selfDestructMs': selfDestructDuration?.inMilliseconds,
        'sdFromChat': selfDestructFromChat,
        'readAt': readAt?.millisecondsSinceEpoch,
        'burnAfterRead': burnAfterRead ? 1 : 0,
        'einmalig': einmalig ? 1 : 0,
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
      // Bestandsdatensaetze kennen das Feld nicht. Sie bekommen den
      // Zeitpunkt beim Laden nachgetragen, sonst laeuft ihre Uhr nie an.
      deliveredAt: map['deliveredAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['deliveredAt'] as int)
          : null,
      status: MessageStatus.values[map['status'] as int],
      // A2: clamp stored milliseconds — non-positive → no self-destruct,
      // cap at 30 days to prevent Duration overflow in downstream timers.
      selfDestructDuration: _decodeSelfDestruct(map['selfDestructMs']),
      selfDestructFromChat: map['sdFromChat'] == true,
      readAt: map['readAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['readAt'] as int)
          : null,
      burnAfterRead: (map['burnAfterRead'] as int?) == 1,
      // Bestandsdatensaetze kennen das Feld nicht und sind gewoehnlich.
      einmalig: (map['einmalig'] as int?) == 1,
      isPasswordProtected: (map['pwProtected'] as int?) == 1,
      passwordUnlocked: (map['pwUnlocked'] as int?) == 1,
      // Fehlt das Feld, stammt der Eintrag aus der Zeit vor den
      // Systemhinweisen — dann ist es eine gewöhnliche Nachricht.
      // Eine unbekannte Nummer darf hier nicht werfen: loadMessages fängt
      // Fehler ab und gibt eine LEERE Liste zurück — ein einziger Eintrag
      // aus einer neueren Version würde sonst den ganzen Verlauf
      // verschwinden lassen. Dann lieber eine gewöhnliche Nachricht.
      systemEvent: _decodeSystemEvent(map['sysEvent']),
    );
  }

  @override
  List<Object?> get props => [id, chatId, senderId, timestamp, status];

  /// Systemereignis aus dem Speicher lesen; Unbekanntes wird zu `null`.
  static SystemEventKind? _decodeSystemEvent(Object? raw) {
    if (raw is! int) return null;
    if (raw < 0 || raw >= SystemEventKind.values.length) return null;
    return SystemEventKind.values[raw];
  }

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
