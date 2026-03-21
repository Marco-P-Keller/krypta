/**
 * Krypta ECC - Firebase Cloud Functions
 *
 * These functions handle server-side message lifecycle:
 * 1. Message TTL cleanup - auto-delete messages after 24h
 * 2. Push notification triggers - notify recipient of new messages
 * 3. Account cleanup - remove orphaned data
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
 * Sends a push notification to the recipient (content-free).
 */
exports.onNewMessage = functions.firestore
  .document("messages/{recipientId}/inbox/{messageId}")
  .onCreate(async (snap, context) => {
    const { recipientId } = context.params;
    const messageData = snap.data();

    // Look up the recipient's FCM token
    const tokenDoc = await db.collection("fcmTokens").doc(recipientId).get();
    if (!tokenDoc.exists) return;

    const token = tokenDoc.data().token;
    if (!token) return;

    // Send content-free notification (no message preview for security)
    await admin.messaging().send({
      token,
      notification: {
        title: "New Message",
        body: "You have a new encrypted message",
      },
      data: {
        type: "new_message",
        senderId: messageData.senderId || "",
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
  });

/**
 * Scheduled function: runs every hour to delete expired messages.
 * Messages older than 24 hours are purged regardless of delivery status.
 */
exports.cleanupExpiredMessages = functions.pubsub
  .schedule("every 1 hours")
  .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 24 * 60 * 60 * 1000)
    );

    const usersSnapshot = await db.collection("messages").listDocuments();

    for (const userDoc of usersSnapshot) {
      const expiredMessages = await userDoc
        .collection("inbox")
        .where("timestamp", "<", cutoff)
        .get();

      const batch = db.batch();
      expiredMessages.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }

    console.log("Expired message cleanup completed");
  });

/**
 * Triggered when a message is marked as delivered.
 * Deletes it from the relay after a short grace period.
 */
exports.onMessageDelivered = functions.firestore
  .document("messages/{recipientId}/inbox/{messageId}")
  .onUpdate(async (change, context) => {
    const after = change.after.data();

    if (after.delivered === true) {
      // Delete after 60 seconds grace period (allows for sync)
      await new Promise((resolve) => setTimeout(resolve, 60000));
      await change.after.ref.delete();
    }
  });
