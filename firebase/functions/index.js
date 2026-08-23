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
 * The app hides behind a calculator — CFBundleDisplayName is "Rechner" / "Calc"
 * — so iOS renders this as:
 *
 *     RECHNER
 *     Tippen zum Öffnen
 *
 * It used to read "New Message / You have a new encrypted message". A
 * calculator announcing encrypted messages gives the entire cover away to
 * anyone glancing at the phone, which is precisely the threat the disguise
 * exists for. The text must therefore say that *something* arrived without
 * hinting at what the app is.
 *
 * Deliberately no `title`: iOS already shows the app name above the body, and
 * a second line would only add surface that has to stay in character.
 *
 * Not localized. Doing that properly needs APNs `loc-key` plus a
 * Localizable.strings in every .lproj, and each of those has to be wired into
 * the Xcode project — not something to do blind without a Mac. All current
 * users are German-speaking, so German is the honest default rather than a
 * half-done mechanism. If the user base widens, localize it properly instead
 * of guessing server-side.
 *
 * Stricter alternative, if the cover matters more than being notified at all:
 * drop `notification` entirely and send a data-only push. The app already
 * fetches through lib/security/transport/privacy_polling.dart, so no message
 * would be lost — the user simply would not learn about it until they open
 * the app. See docs/FIREBASE_FUNCTIONS.md.
 */
const COVER_NOTIFICATION = {
  body: "Tippen zum Öffnen",
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
