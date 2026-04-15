import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore service — ephemeral message relay, key exchange, typing, acks.
///
/// The server NEVER stores plaintext. All message payloads are E2E encrypted.
/// Messages are deleted after delivery or after TTL (24h max).
class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // --- Public Key Registry ---

  Future<void> registerPublicKey({
    required String userId,
    required String publicKeyBase64,
  }) async {
    await _db.collection('publicKeys').doc(userId).set({
      'publicKey': publicKeyBase64,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> getPublicKey(String userId) async {
    final doc = await _db.collection('publicKeys').doc(userId).get();
    return doc.data()?['publicKey'] as String?;
  }

  Future<bool> userExists(String userId) async {
    final doc = await _db.collection('publicKeys').doc(userId).get();
    return doc.exists;
  }

  // --- PreKey Bundle ---

  Future<void> publishPreKeyBundle({
    required String userId,
    required Map<String, dynamic> bundle,
  }) async {
    await _db.collection('prekeys').doc(userId).set({
      ...bundle,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getPreKeyBundle(String userId) async {
    final doc = await _db.collection('prekeys').doc(userId).get();
    return doc.data();
  }

  /// Remove consumed one-time prekey from the bundle.
  Future<void> consumeOneTimePreKey(String userId) async {
    await _db.collection('prekeys').doc(userId).update({
      'opk': FieldValue.delete(),
      'opkId': FieldValue.delete(),
    });
  }

  // --- Message Relay ---

  Future<String> sendEncryptedMessage({
    required String senderId,
    required String recipientId,
    required String messageId,
    required Map<String, String> encryptedPayload,
    int? selfDestructMs,
    bool burnAfterRead = false,
    bool isPasswordProtected = false,
  }) async {
    final data = <String, dynamic>{
      'sid': senderId,
      'mid': messageId,
      'p': encryptedPayload,
      'ts': FieldValue.serverTimestamp(),
      'sd': selfDestructMs,
      'bar': burnAfterRead,
      'pw': isPasswordProtected,
    };

    final ref = await _db
        .collection('messages')
        .doc(recipientId)
        .collection('inbox')
        .add(data);
    return ref.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> listenForMessages(String userId) {
    return _db
        .collection('messages')
        .doc(userId)
        .collection('inbox')
        .orderBy('ts', descending: false)
        .snapshots();
  }

  Future<void> deleteRelayedMessage(String userId, String firestoreDocId) async {
    await _db
        .collection('messages')
        .doc(userId)
        .collection('inbox')
        .doc(firestoreDocId)
        .delete();
  }

  // --- Delivery & Read Acknowledgments ---

  Future<void> sendAck({
    required String recipientId,
    required String messageId,
    required String type,
  }) async {
    await _db
        .collection('acks')
        .doc(recipientId)
        .collection('inbox')
        .add({
      'mid': messageId,
      'type': type,
      'ts': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> listenForAcks(String userId) {
    return _db
        .collection('acks')
        .doc(userId)
        .collection('inbox')
        .snapshots();
  }

  Future<void> deleteAck(String userId, String ackDocId) async {
    await _db
        .collection('acks')
        .doc(userId)
        .collection('inbox')
        .doc(ackDocId)
        .delete();
  }

  // --- Typing Indicators ---

  Future<void> setTyping({
    required String recipientId,
    required String senderId,
    required bool isTyping,
  }) async {
    await _db.collection('typing').doc(recipientId).set({
      senderId: isTyping ? FieldValue.serverTimestamp() : FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> listenForTyping(String userId) {
    return _db.collection('typing').doc(userId).snapshots();
  }

  // --- FCM Token ---

  Future<void> registerFcmToken({
    required String userId,
    required String token,
  }) async {
    await _db.collection('fcmTokens').doc(userId).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // --- Cleanup ---

  Future<void> deleteAllUserData(String userId) async {
    final batch = _db.batch();

    final messages = await _db
        .collection('messages').doc(userId).collection('inbox').get();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }

    final acks = await _db
        .collection('acks').doc(userId).collection('inbox').get();
    for (final doc in acks.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(_db.collection('publicKeys').doc(userId));
    batch.delete(_db.collection('prekeys').doc(userId));
    batch.delete(_db.collection('typing').doc(userId));
    batch.delete(_db.collection('fcmTokens').doc(userId));

    await batch.commit();
  }
}
