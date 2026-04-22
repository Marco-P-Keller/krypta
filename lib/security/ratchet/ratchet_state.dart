import 'dart:convert';
import 'dart:typed_data';

/// Immutable Double Ratchet session state for one chat.
///
/// Based on the Signal Double Ratchet spec:
/// https://signal.org/docs/specifications/doubleratchet/
class RatchetState {
  final Uint8List rootKey;
  final Uint8List? sendingChainKey;
  final Uint8List? receivingChainKey;
  final Uint8List dhSendingPublic;
  final Uint8List dhSendingPrivate;
  final Uint8List? dhReceivingPublic;
  final int sendMessageNumber;
  final int receiveMessageNumber;
  final int previousChainLength;

  /// Map from "base64(dhPub):msgNum" → message key (32 bytes).
  /// Holds keys for out-of-order messages.
  final Map<String, Uint8List> skippedMessageKeys;

  /// Creation timestamps (ms since epoch) for skipped keys.
  /// Keys older than 30 days are pruned to preserve forward secrecy.
  final Map<String, int> skippedKeyTimestamps;

  const RatchetState({
    required this.rootKey,
    this.sendingChainKey,
    this.receivingChainKey,
    required this.dhSendingPublic,
    required this.dhSendingPrivate,
    this.dhReceivingPublic,
    this.sendMessageNumber = 0,
    this.receiveMessageNumber = 0,
    this.previousChainLength = 0,
    Map<String, Uint8List>? skippedMessageKeys,
    Map<String, int>? skippedKeyTimestamps,
  }) : skippedMessageKeys = skippedMessageKeys ?? const {},
       skippedKeyTimestamps = skippedKeyTimestamps ?? const {};

  RatchetState copyWith({
    Uint8List? rootKey,
    Object? sendingChainKey = _absent,
    Object? receivingChainKey = _absent,
    Uint8List? dhSendingPublic,
    Uint8List? dhSendingPrivate,
    Object? dhReceivingPublic = _absent,
    int? sendMessageNumber,
    int? receiveMessageNumber,
    int? previousChainLength,
    Map<String, Uint8List>? skippedMessageKeys,
    Map<String, int>? skippedKeyTimestamps,
  }) {
    return RatchetState(
      rootKey: rootKey ?? this.rootKey,
      sendingChainKey: sendingChainKey == _absent
          ? this.sendingChainKey
          : sendingChainKey as Uint8List?,
      receivingChainKey: receivingChainKey == _absent
          ? this.receivingChainKey
          : receivingChainKey as Uint8List?,
      dhSendingPublic: dhSendingPublic ?? this.dhSendingPublic,
      dhSendingPrivate: dhSendingPrivate ?? this.dhSendingPrivate,
      dhReceivingPublic: dhReceivingPublic == _absent
          ? this.dhReceivingPublic
          : dhReceivingPublic as Uint8List?,
      sendMessageNumber: sendMessageNumber ?? this.sendMessageNumber,
      receiveMessageNumber: receiveMessageNumber ?? this.receiveMessageNumber,
      previousChainLength: previousChainLength ?? this.previousChainLength,
      skippedMessageKeys: skippedMessageKeys ?? this.skippedMessageKeys,
      skippedKeyTimestamps: skippedKeyTimestamps ?? this.skippedKeyTimestamps,
    );
  }

  Map<String, dynamic> toMap() => {
        'rk': base64Encode(rootKey),
        'cks': sendingChainKey != null ? base64Encode(sendingChainKey!) : null,
        'ckr': receivingChainKey != null ? base64Encode(receivingChainKey!) : null,
        'dhsp': base64Encode(dhSendingPublic),
        'dhsk': base64Encode(dhSendingPrivate),
        'dhrp': dhReceivingPublic != null ? base64Encode(dhReceivingPublic!) : null,
        'ns': sendMessageNumber,
        'nr': receiveMessageNumber,
        'pn': previousChainLength,
        'skip': skippedMessageKeys.map((k, v) => MapEntry(k, base64Encode(v))),
        if (skippedKeyTimestamps.isNotEmpty)
          'skipTs': skippedKeyTimestamps,
      };

  factory RatchetState.fromMap(Map<String, dynamic> map) {
    final skipRaw = (map['skip'] as Map<String, dynamic>?) ?? {};
    final skipTsRaw = (map['skipTs'] as Map<String, dynamic>?) ?? {};
    return RatchetState(
      rootKey: base64Decode(map['rk'] as String),
      sendingChainKey:
          map['cks'] != null ? base64Decode(map['cks'] as String) : null,
      receivingChainKey:
          map['ckr'] != null ? base64Decode(map['ckr'] as String) : null,
      dhSendingPublic: base64Decode(map['dhsp'] as String),
      dhSendingPrivate: base64Decode(map['dhsk'] as String),
      dhReceivingPublic:
          map['dhrp'] != null ? base64Decode(map['dhrp'] as String) : null,
      sendMessageNumber: (map['ns'] as int?) ?? 0,
      receiveMessageNumber: (map['nr'] as int?) ?? 0,
      previousChainLength: (map['pn'] as int?) ?? 0,
      skippedMessageKeys: skipRaw.map((k, v) => MapEntry(k, base64Decode(v as String))),
      skippedKeyTimestamps: skipTsRaw.map((k, v) => MapEntry(k, v as int)),
    );
  }
}

const _absent = Object();
