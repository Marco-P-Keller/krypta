/**
 * Krypta ECC - Firebase Cloud Functions
 *
 * These functions handle server-side message lifecycle:
 * 1. Message TTL cleanup - auto-delete messages after 24h
 * 2. Push notification triggers - notify recipient of new messages
 *
 * SECURITY: The server NEVER has access to plaintext messages.
 * All payloads are encrypted ciphertext. The server is a dumb relay.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Triggered when a new encrypted message is written to a user's inbox.
 * Sends a content-free push notification to the recipient.
 *
 * Firestore field mapping (from FirestoreService):
 *   sid  = sender ID
 *   mid  = message ID
 *   p    = encrypted payload
 *   ts   = server timestamp
 *   sd   = self-destruct ms
 *   bar  = burn after read
 *   pw   = password protected
 */
exports.onNewMessage = functions.firestore
  .document("messages/{recipientId}/inbox/{messageId}")
  .onCreate(async (snap, context) => {
    const { recipientId } = context.params;
    const messageData = snap.data();

    const tokenDoc = await db.collection("fcmTokens").doc(recipientId).get();
    if (!tokenDoc.exists) return;

    const token = tokenDoc.data().token;
    if (!token) return;

    try {
      // SECURITY: Do NOT include senderId or any message metadata in push.
      // FCM payloads are logged by Google — including sender ID would leak
      // who is communicating with whom (communication pattern metadata).
      // The app retrieves sender info from its encrypted inbox on wake.
      await admin.messaging().send({
        token,
        notification: {
          title: "New Message",
          body: "You have a new encrypted message",
        },
        data: {
          type: "new_message",
        },
        apns: {
          payload: {
            aps: {
              "content-available": 1,
              sound: "default",
            },
          },
        },
      });
    } catch (err) {
      if (
        err.code === "messaging/registration-token-not-registered" ||
        err.code === "messaging/invalid-registration-token"
      ) {
        await db.collection("fcmTokens").doc(recipientId).delete();
      }
      console.error("Push notification failed:", err.message);
    }
  });

/**
 * Scheduled function: runs every hour to delete expired messages.
 * Messages older than 24 hours are purged regardless of delivery status.
 *
 * Uses the 'ts' field (server timestamp) set by FirestoreService.
 *
 * Pagination: drains each user's expired-message set in 500-doc batches
 * until empty. Without the loop, a user with > 500 stale messages would
 * only get 500 cleared per hour-tick, weakening the 24h TTL guarantee
 * under flood / abuse.
 */
exports.cleanupExpiredMessages = functions.pubsub
  .schedule("every 1 hours")
  .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 24 * 60 * 60 * 1000)
    );

    const usersSnapshot = await db.collection("messages").listDocuments();
    let totalDeleted = 0;

    for (const userDoc of usersSnapshot) {
      // Drain this user's expired messages until none remain. The cutoff
      // is fixed at function start so no new doc can re-enter the query
      // mid-drain (new messages have ts == request.time > cutoff).
      // eslint-disable-next-line no-constant-condition
      while (true) {
        const expiredMessages = await userDoc
          .collection("inbox")
          .where("ts", "<", cutoff)
          .limit(500) // Firestore batch limit: max 500 operations
          .get();

        if (expiredMessages.empty) break;

        const batch = db.batch();
        expiredMessages.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        totalDeleted += expiredMessages.size;

        if (expiredMessages.size < 500) break;
      }
    }

    console.log(`Expired message cleanup: deleted ${totalDeleted} messages`);
  });
