import 'dart:convert';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';

class Contact extends Equatable {
  final String id;
  final String displayName;
  final Uint8List publicKey;
  final DateTime addedAt;

  const Contact({
    required this.id,
    required this.displayName,
    required this.publicKey,
    required this.addedAt,
  });

  String get publicKeyBase64 => base64Encode(publicKey);
  String get shortId => id.length > 8 ? '${id.substring(0, 8)}...' : id;

  Contact copyWith({String? displayName}) {
    return Contact(
      id: id,
      displayName: displayName ?? this.displayName,
      publicKey: publicKey,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'publicKey': base64Encode(publicKey),
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      publicKey: base64Decode(map['publicKey'] as String),
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
    );
  }

  @override
  List<Object?> get props => [id];
}
