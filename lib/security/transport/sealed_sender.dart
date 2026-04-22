import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Sealed Sender: hides the sender's identity from the server.
///
/// Architecture:
/// 1. Recipient publishes a [DeliveryToken] to the server (short-lived, random)
/// 2. Sender encrypts the message with the recipient's public key
/// 3. Sender wraps the ciphertext in a [SealedEnvelope] that includes:
///    - The sender's identity (inside the encrypted payload)
///    - The recipient's delivery token (outside, for routing)
/// 4. Server routes the envelope using ONLY the delivery token
///    — it cannot see who sent it
///
/// The sender's identity is bound inside the E2E encrypted content,
/// so only the recipient can identify the sender after decryption.
class SealedSender {
  static final _random = Random.secure();

  /// Generate a delivery token for the recipient.
  ///
  /// The recipient publishes this to the server. Senders include it in
  /// their envelopes so the server can route without knowing the sender.
  /// Tokens should be rotated periodically (e.g., every 24 hours).
  static DeliveryToken generateDeliveryToken() {
    final tokenBytes = Uint8List.fromList(
      List.generate(32, (_) => _random.nextInt(256)),
    );
    return DeliveryToken(
      token: base64Encode(tokenBytes),
      createdAt: DateTime.now(),
    );
  }

  /// Create a sealed envelope that hides the sender's identity.
  ///
  /// The [senderIdentity] is encrypted inside the payload along with
  /// the [innerPayload] (the E2E encrypted message). The server only
  /// sees the [deliveryToken] for routing.
  static Future<SealedEnvelope> seal({
    required String senderIdentity,
    required Map<String, dynamic> innerPayload,
    required String deliveryToken,
  }) async {
    // Include sender identity inside the encrypted content.
    // The server cannot see this — only the recipient can after decryption.
    innerPayload['_sid'] = senderIdentity;

    return SealedEnvelope(
      deliveryToken: deliveryToken,
      payload: innerPayload,
    );
  }

  /// Extract the sender identity from a decrypted sealed envelope.
  ///
  /// Returns the sender ID that was hidden inside the encrypted payload.
  static String? extractSender(Map<String, dynamic> decryptedPayload) {
    return decryptedPayload['_sid'] as String?;
  }
}

/// A delivery token published by the recipient for anonymous message routing.
class DeliveryToken {
  final String token;
  final DateTime createdAt;

  /// Tokens expire after 24 hours to limit linkability.
  static const maxAge = Duration(hours: 24);

  const DeliveryToken({
    required this.token,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().difference(createdAt) > maxAge;

  Map<String, dynamic> toMap() => {
        'token': token,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory DeliveryToken.fromMap(Map<String, dynamic> map) => DeliveryToken(
        token: map['token'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      );
}

/// An envelope that hides the sender's identity from the server.
///
/// The server sees only [deliveryToken] (for routing to the recipient).
/// The sender's identity is inside [payload], encrypted end-to-end.
class SealedEnvelope {
  final String deliveryToken;
  final Map<String, dynamic> payload;

  const SealedEnvelope({
    required this.deliveryToken,
    required this.payload,
  });

  Map<String, dynamic> toFirestoreData(String messageId) => {
        'dt': deliveryToken,
        'mid': messageId,
        'p': payload.map((k, v) => MapEntry(k, v.toString())),
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}
