/**
 * Krypta ECC - Firebase Cloud Functions
 *
 * These functions handle server-side message lifecycle:
 * 1. Push notification triggers - notify recipient of new messages
 * 2. Message TTL cleanup - auto-delete messages after 24h
 *
 * SECURITY: The server NEVER has access to plaintext messages.
 * All payloads are encrypted ciphertext. The server is a dumb relay.
 *
 * ---------------------------------------------------------------------------
 * RUNTIME: these are still 1st-gen functions, deliberately.
 *
 * Node 18 was decommissioned by Google, so the previous configuration could
 * not be deployed at all. Runtime is now nodejs22 (firebase.json +
 * package.json engines), on firebase-functions v6 with the v1 API imported
 * explicitly.
 *
 * Moving to 2nd-gen (`firebase-functions/v2`, onDocumentCreated / onSchedule)
 * is the better long-term shape, but it is NOT a drop-in: a function already
 * deployed as 1st-gen cannot be converted in place — it has to be deleted and
 * recreated under the same name, which drops events in between. Since nobody
 * here can see the deployed state of `kryptaecc`, that migration is left as a
 * deliberate, separate step. See docs/FIREBASE_FUNCTIONS.md.
 * ---------------------------------------------------------------------------
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Wording of the push alert that lands on the lock screen.
 *
 * iOS renders it under the app name, which since d62998f is "Krypta ECC" and
 * no longer a calculator alias:
 *
 *     KRYPTA ECC
 *     Du hast eine neue Nachricht erhalten
 *
 * Daniel asked for this wording, replacing the neutral "Tippen zum Oeffnen".
 * What it gives up: a glance at the lock screen now reveals THAT something
 * arrived, not merely that the app wants attention. Under a display name
 * already reading "Krypta ECC" that is a small step. On Android the label is
 * still "Calc", so there it costs more.
 *
 * Never a sender, never content, never a preview. Those would have to travel
 * through FCM, which Google logs.
 *
 * Deliberately no `title`: iOS already shows the app name above the body.
 *
 * ONE text for both cases, and the server could not do better. A contact
 * request is an ordinary inbox document; the `_rq` marker sits inside the
 * ciphertext. Writing "Du hast eine Anfrage erhalten" would require the sender
 * to attach a plaintext flag, telling Firebase exactly when a new connection
 * between two accounts is formed. Telling the two apart belongs in an iOS
 * Notification Service Extension that decrypts on the device; that needs a new
 * Xcode target and a Mac.
 *
 * Not localized. Doing that properly needs APNs `loc-key` plus a
 * Localizable.strings in every .lproj, and each of those has to be wired into
 * the Xcode project - not something to do blind without a Mac. All current
 * users are German-speaking, so German is the honest default rather than a
 * half-done mechanism. If the user base widens, localize it properly instead
 * of guessing server-side.
 *
 * Stricter alternative, if the cover matters more than being notified at all:
 * drop `notification` entirely and send a data-only push. The app already
 * fetches through lib/security/transport/privacy_polling.dart, so no message
 * would be lost - the user simply would not learn about it until they open
 * the app. See docs/FIREBASE_FUNCTIONS.md.
 */
const COVER_NOTIFICATION = {
  body: "Du hast eine neue Nachricht erhalten",
};

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
        notification: COVER_NOTIFICATION,
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
