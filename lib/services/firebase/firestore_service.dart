import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore service — ephemeral message relay, key exchange, acks.
///
/// Privacy-by-design principles:
/// - Server NEVER stores plaintext — all payloads are E2E encrypted
/// - Messages are deleted immediately after delivery (ephemeral relay)
/// - ACKs contain minimal fields (message ID + type only, no timestamps)
/// - No typing indicators — zero interaction metadata leaked
/// - FCM tokens are ephemeral and deletable on demand
class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // --- Public Key Registry ---

  /// H2-Network (audit 2026-05): Firestore rules require `updatedAt ==
  /// request.time` for create/update on this collection — without it, the
  /// rule evaluates `undefined == time` to false and the write is denied.
  /// Use `FieldValue.serverTimestamp()` so the server stamps the time the
  /// rule then compares against.
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

  // --- Key Transparency Commitments ---

  /// Publish a key commitment to the transparency log.
  ///
  /// Commitments are stored by epoch, forming an append-only log.
  /// The server cannot forge entries (Ed25519-signed by the key owner)
  /// but could attempt to serve different entries to different clients,
  /// which is detected by the ConsistencyChecker gossip protocol.
  Future<void> publishKeyCommitment({
    required String userId,
    required Map<String, dynamic> commitment,
    required int epoch,
  }) async {
    await _db
        .collection('keyCommitments')
        .doc(userId)
        .collection('log')
        .doc(epoch.toString())
        .set(commitment);
  }

  /// Fetch all key commitments for a user, ordered by epoch.
  Future<List<Map<String, dynamic>>> getKeyCommitments(String userId) async {
    final snapshot = await _db
        .collection('keyCommitments')
        .doc(userId)
        .collection('log')
        .orderBy('e')
        .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  /// Fetch key commitments since a specific epoch (for incremental sync).
  Future<List<Map<String, dynamic>>> getKeyCommitmentsSince(
      String userId, int sinceEpoch) async {
    final snapshot = await _db
        .collection('keyCommitments')
        .doc(userId)
        .collection('log')
        .where('e', isGreaterThan: sinceEpoch)
        .orderBy('e')
        .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  /// Get the latest key commitment for a user.
  Future<Map<String, dynamic>?> getLatestKeyCommitment(String userId) async {
    final snapshot = await _db
        .collection('keyCommitments')
        .doc(userId)
        .collection('log')
        .orderBy('e', descending: true)
        .limit(1)
        .get();
    return snapshot.docs.isEmpty ? null : snapshot.docs.first.data();
  }

  // --- PreKey Bundle ---

  Future<void> publishPreKeyBundle({
    required String userId,
    required Map<String, dynamic> bundle,
  }) async {
    // H2-Network: rules require updatedAt == request.time — ensure it is set.
    final payload = {...bundle, 'updatedAt': FieldValue.serverTimestamp()};
    await _db.collection('prekeys').doc(userId).set(payload);
  }

  Future<Map<String, dynamic>?> getPreKeyBundle(String userId) async {
    final doc = await _db.collection('prekeys').doc(userId).get();
    return doc.data();
  }

  /// Atomically claim and remove a one-time prekey from the bundle.
  ///
  /// Uses a Firestore transaction to prevent race conditions where two
  /// simultaneous session initiations both consume the same OTP, producing
  /// overlapping session keys. Returns true if the OTP was successfully
  /// claimed (i.e. it still existed at the time of the transaction).
  Future<bool> consumeOneTimePreKey(String userId) async {
    return _db.runTransaction((txn) async {
      final ref = _db.collection('prekeys').doc(userId);
      final snapshot = await txn.get(ref);
      if (!snapshot.exists) return false;
      final data = snapshot.data()!;
      if (data['opk'] == null) return false; // Already consumed
      txn.update(ref, {
        'opk': FieldValue.delete(),
        'opkId': FieldValue.delete(),
      });
      return true;
    });
  }

  // --- Message Relay (ephemeral — deleted after delivery) ---

  Future<String> sendEncryptedMessage({
    required String senderId,
    required String recipientId,
    required String messageId,
    // H2-Proto (audit 2026-05): widened from Map<String, String> so callers
    // can pass native int/bool fields (`v`, `pv`, `ns`, `pn`) without
    // toString() coercion. Firestore accepts the JSON-compatible types.
    required Map<String, dynamic> encryptedPayload,
  }) async {
    // Minimal metadata: sender ID, message ID, encrypted payload.
    // Server timestamp only for ordering — deleted after delivery.
    // Message flags (self-destruct, burn-after-read, password) are
    // INSIDE the encrypted payload — invisible to the server.
    final data = <String, dynamic>{
      'sid': senderId,
      'mid': messageId,
      'p': encryptedPayload,
      'ts': FieldValue.serverTimestamp(),
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

  // --- Legacy Plaintext ACKs (DEPRECATED) ─────────────────────────────────
  //
  // DEPRECATED: These methods send unencrypted ACKs through a separate
  // Firestore collection. Control messages (ACKs, deletes, reads, unlocks)
  // now travel through the encrypted message channel via ControlMessage.
  // These methods are retained only for potential migration cleanup.
  // DO NOT use in new code.

  @Deprecated('Use ControlMessage through encrypted message channel instead')
  Future<void> sendAck({
    required String senderId,
    required String recipientId,
    required String messageId,
    required String type,
  }) async {
    final typeCode = switch (type) {
      'delivered' => 'd',
      'read' => 'r',
      'unlock' => 'u',
      'delete' => 'x',
      _ => '?',
    };
    await _db
        .collection('acks')
        .doc(recipientId)
        .collection('inbox')
        .add({
      'mid': messageId,
      't': typeCode,
      'sid': senderId,
    });
  }

  @Deprecated('ACK listener removed — control messages arrive via inbox')
  Stream<QuerySnapshot<Map<String, dynamic>>> listenForAcks(String userId) {
    return _db
        .collection('acks')
        .doc(userId)
        .collection('inbox')
        .snapshots();
  }

  @Deprecated('ACK cleanup — control messages deleted via inbox')
  Future<void> deleteAck(String userId, String ackDocId) async {
    await _db
        .collection('acks')
        .doc(userId)
        .collection('inbox')
        .doc(ackDocId)
        .delete();
  }

  // --- Delivery Tokens (Sealed Sender) ---

  /// Publish a delivery token for sealed sender routing.
  /// Recipients publish tokens so senders can route messages anonymously.
  Future<void> publishDeliveryToken({
    required String userId,
    required String token,
  }) async {
    // H2-Network: matches the new deliveryTokens rule's optional updatedAt.
    await _db.collection('deliveryTokens').doc(userId).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get a recipient's delivery token for sealed sender.
  Future<String?> getDeliveryToken(String userId) async {
    final doc = await _db.collection('deliveryTokens').doc(userId).get();
    return doc.data()?['token'] as String?;
  }

  /// Delete the delivery token (on logout, wipe, or rotation).
  Future<void> deleteDeliveryToken(String userId) async {
    await _db.collection('deliveryTokens').doc(userId).delete();
  }

  // --- FCM Token (ephemeral) ---

  Future<void> registerFcmToken({
    required String userId,
    required String token,
  }) async {
    // H2-Network: rules require updatedAt == request.time.
    await _db.collection('fcmTokens').doc(userId).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete FCM token — called on logout, wipe, or token rotation.
  Future<void> deleteFcmToken(String userId) async {
    await _db.collection('fcmTokens').doc(userId).delete();
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

    final commitments = await _db
        .collection('keyCommitments').doc(userId).collection('log').get();
    for (final doc in commitments.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(_db.collection('publicKeys').doc(userId));
    batch.delete(_db.collection('prekeys').doc(userId));
    batch.delete(_db.collection('fcmTokens').doc(userId));
    batch.delete(_db.collection('deliveryTokens').doc(userId));

    await batch.commit();
  }
}
