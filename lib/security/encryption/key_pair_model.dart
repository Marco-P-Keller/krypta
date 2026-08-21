import 'dart:convert';
import 'dart:typed_data';

class KryptaKeyPair {
  final Uint8List privateKey;
  final Uint8List publicKey;

  const KryptaKeyPair({
    required this.privateKey,
    required this.publicKey,
  });

  String get publicKeyBase64 => base64Encode(publicKey);
  String get privateKeyBase64 => base64Encode(privateKey);

  factory KryptaKeyPair.fromBase64({
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) {
    return KryptaKeyPair(
      privateKey: base64Decode(privateKeyBase64),
      publicKey: base64Decode(publicKeyBase64),
    );
  }

  @override
  String toString() => 'KryptaKeyPair(${publicKey.length}B)';
}

class EncryptedPayload {
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List mac;
  final Uint8List ephemeralPublicKey;

  const EncryptedPayload({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
    required this.ephemeralPublicKey,
  });

  EncryptedPayload copyWith({
    Uint8List? ciphertext,
    Uint8List? nonce,
    Uint8List? mac,
    Uint8List? ephemeralPublicKey,
  }) {
    return EncryptedPayload(
      ciphertext: ciphertext ?? this.ciphertext,
      nonce: nonce ?? this.nonce,
      mac: mac ?? this.mac,
      ephemeralPublicKey: ephemeralPublicKey ?? this.ephemeralPublicKey,
    );
  }

  Map<String, String> toMap() => {
        'c': base64Encode(ciphertext),
        'n': base64Encode(nonce),
        'm': base64Encode(mac),
        'e': base64Encode(ephemeralPublicKey),
      };

  factory EncryptedPayload.fromMap(Map<String, dynamic> map) {
    return EncryptedPayload(
      ciphertext: base64Decode(map['c'] as String),
      nonce: base64Decode(map['n'] as String),
      mac: base64Decode(map['m'] as String),
      ephemeralPublicKey: base64Decode(map['e'] as String),
    );
  }
}
