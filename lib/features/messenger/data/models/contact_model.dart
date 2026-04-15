import 'dart:convert';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';

class Contact extends Equatable {
  final String id;
  final String displayName;
  final Uint8List publicKey;
  final DateTime addedAt;

  /// Whether we have verified this contact's identity (QR / fingerprint).
  final bool isVerified;

  /// Previous public key — set when a key change is detected.
  /// Null if key has never changed.
  final Uint8List? previousPublicKey;

  const Contact({
    required this.id,
    required this.displayName,
    required this.publicKey,
    required this.addedAt,
    this.isVerified = false,
    this.previousPublicKey,
  });

  String get publicKeyBase64 => base64Encode(publicKey);
  String get shortId => id.length > 8 ? '${id.substring(0, 8)}...' : id;
  bool get hasKeyChanged => previousPublicKey != null;

  Contact copyWith({
    String? displayName,
    Uint8List? publicKey,
    bool? isVerified,
    Object? previousPublicKey = _sentinel,
  }) {
    return Contact(
      id: id,
      displayName: displayName ?? this.displayName,
      publicKey: publicKey ?? this.publicKey,
      addedAt: addedAt,
      isVerified: isVerified ?? this.isVerified,
      previousPublicKey: previousPublicKey == _sentinel
          ? this.previousPublicKey
          : previousPublicKey as Uint8List?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'publicKey': base64Encode(publicKey),
        'addedAt': addedAt.millisecondsSinceEpoch,
        'verified': isVerified ? 1 : 0,
        if (previousPublicKey != null)
          'prevPubKey': base64Encode(previousPublicKey!),
      };

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      publicKey: base64Decode(map['publicKey'] as String),
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      isVerified: (map['verified'] as int?) == 1,
      previousPublicKey: map['prevPubKey'] != null
          ? base64Decode(map['prevPubKey'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id];
}

const _sentinel = Object();
