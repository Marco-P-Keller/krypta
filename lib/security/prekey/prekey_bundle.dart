import 'dart:convert';
import 'dart:typed_data';

/// A PreKey bundle published to Firestore for offline session initiation.
///
/// Contains:
/// - Identity public key (long-term, for verification)
/// - Signed prekey (medium-term, rotated periodically)
/// - Signature over the signed prekey (Ed25519 from identity key)
/// - One-time prekey (consumed once per new session)
class PreKeyBundle {
  final Uint8List identityPublicKey;
  final Uint8List signedPreKeyPublic;
  final Uint8List signedPreKeySignature;
  final int signedPreKeyId;
  final Uint8List? oneTimePreKeyPublic;
  final int? oneTimePreKeyId;
  /// Ed25519 signing public key (derived from identity private key).
  /// Used to verify signedPreKeySignature. Null for legacy v1 bundles.
  final Uint8List? signingPublicKey;

  const PreKeyBundle({
    required this.identityPublicKey,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    required this.signedPreKeyId,
    this.oneTimePreKeyPublic,
    this.oneTimePreKeyId,
    this.signingPublicKey,
  });

  Map<String, dynamic> toMap() => {
        'ik': base64Encode(identityPublicKey),
        'spk': base64Encode(signedPreKeyPublic),
        'spks': base64Encode(signedPreKeySignature),
        'spkId': signedPreKeyId,
        if (oneTimePreKeyPublic != null) 'opk': base64Encode(oneTimePreKeyPublic!),
        if (oneTimePreKeyId != null) 'opkId': oneTimePreKeyId,
        if (signingPublicKey != null) 'sigPk': base64Encode(signingPublicKey!),
      };

  factory PreKeyBundle.fromMap(Map<String, dynamic> map) => PreKeyBundle(
        identityPublicKey: base64Decode(map['ik'] as String),
        signedPreKeyPublic: base64Decode(map['spk'] as String),
        signedPreKeySignature: base64Decode(map['spks'] as String),
        signedPreKeyId: map['spkId'] as int,
        oneTimePreKeyPublic:
            map['opk'] != null ? base64Decode(map['opk'] as String) : null,
        oneTimePreKeyId: map['opkId'] as int?,
        signingPublicKey:
            map['sigPk'] != null ? base64Decode(map['sigPk'] as String) : null,
      );
}

/// Local record of a signed prekey (private key stored on device).
class SignedPreKey {
  final int id;
  final Uint8List publicKey;
  final Uint8List privateKey;
  final DateTime createdAt;

  const SignedPreKey({
    required this.id,
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'pub': base64Encode(publicKey),
        'priv': base64Encode(privateKey),
        'ts': createdAt.millisecondsSinceEpoch,
      };

  factory SignedPreKey.fromMap(Map<String, dynamic> map) => SignedPreKey(
        id: map['id'] as int,
        publicKey: base64Decode(map['pub'] as String),
        privateKey: base64Decode(map['priv'] as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      );
}

/// A one-time prekey (consumed on first use).
class OneTimePreKey {
  final int id;
  final Uint8List publicKey;
  final Uint8List privateKey;

  const OneTimePreKey({
    required this.id,
    required this.publicKey,
    required this.privateKey,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'pub': base64Encode(publicKey),
        'priv': base64Encode(privateKey),
      };

  factory OneTimePreKey.fromMap(Map<String, dynamic> map) => OneTimePreKey(
        id: map['id'] as int,
        publicKey: base64Decode(map['pub'] as String),
        privateKey: base64Decode(map['priv'] as String),
      );
}
