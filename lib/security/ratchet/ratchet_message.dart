import 'dart:convert';
import 'dart:typed_data';

/// Ratchet message header — included in AAD and transmitted unencrypted.
class RatchetHeader {
  final Uint8List dhPublicKey;   // Sender's current ratchet DH public key
  final int messageNumber;       // Ns: position in current sending chain
  final int previousChainLength; // PN: length of previous sending chain

  const RatchetHeader({
    required this.dhPublicKey,
    required this.messageNumber,
    required this.previousChainLength,
  });

  /// Serialize to bytes for use as AAD.
  Uint8List toBytes() {
    final dhB64 = base64Encode(dhPublicKey);
    final json = '{"dh":"$dhB64","n":$messageNumber,"pn":$previousChainLength}';
    return Uint8List.fromList(utf8.encode(json));
  }

  Map<String, dynamic> toMap() => {
        'dh': base64Encode(dhPublicKey),
        'n': messageNumber,
        'pn': previousChainLength,
      };

  factory RatchetHeader.fromMap(Map<String, dynamic> map) => RatchetHeader(
        dhPublicKey: base64Decode(map['dh'] as String),
        messageNumber: map['n'] as int,
        previousChainLength: map['pn'] as int,
      );
}

/// The encrypted part of a ratchet message.
class EncryptedRatchetMessage {
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List mac;

  const EncryptedRatchetMessage({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  Map<String, String> toMap() => {
        'c': base64Encode(ciphertext),
        'nc': base64Encode(nonce),
        'm': base64Encode(mac),
      };

  factory EncryptedRatchetMessage.fromMap(Map<String, dynamic> map) =>
      EncryptedRatchetMessage(
        ciphertext: base64Decode(map['c'] as String),
        nonce: base64Decode(map['nc'] as String),
        mac: base64Decode(map['m'] as String),
      );
}

/// Full ratchet message = header + encrypted ciphertext.
class RatchetMessage {
  final RatchetHeader header;
  final EncryptedRatchetMessage ciphertext;

  const RatchetMessage({required this.header, required this.ciphertext});

  /// Serializes to the Firestore payload map (v=2).
  Map<String, dynamic> toPayloadMap() => {
        'v': 2,
        ...header.toMap(),
        ...ciphertext.toMap(),
      };

  factory RatchetMessage.fromPayloadMap(Map<String, dynamic> map) =>
      RatchetMessage(
        header: RatchetHeader.fromMap(map),
        ciphertext: EncryptedRatchetMessage.fromMap(map),
      );
}
