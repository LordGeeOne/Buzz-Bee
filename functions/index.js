/**
 * Cloud Functions for Buzz Bee.
 *
 * Listens for new messages in any connection's messages subcollection and
 * multicasts an FCM push notification to the recipient — but only when the
 * recipient is NOT currently viewing the chat (per `viewing.{uid}` flag on
 * the connection doc, which the Flutter ChatScreen toggles).
 */

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

exports.onBuzzMessageCreated = onDocumentCreated(
    "connections/{connId}/messages/{msgId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const msg = snap.data() || {};
      const type = msg.type;
      if (type !== "buzz" && type !== "text" && type !== "voice") return;

      const fromUid = msg.fromUid;
      const connId = event.params.connId;

      // Resolve the recipient from the connection's users array.
      const connSnap = await db.collection("connections").doc(connId).get();
      const conn = connSnap.data();
      if (!conn || !Array.isArray(conn.users)) return;
      const recipient = conn.users.find((u) => u !== fromUid);
      if (!recipient) return;

      // Skip the push if the recipient already has the chat open. Their
      // device handles haptic feedback locally; a notification would just
      // duplicate it.
      const viewing = conn.viewing || {};
      if (viewing[recipient] === true) {
        logger.info("recipient is viewing chat; skipping push", {recipient});
        return;
      }

      // Load recipient's fcm tokens and sender's display name.
      const [recipientSnap, senderSnap] = await Promise.all([
        db.collection("users").doc(recipient).get(),
        db.collection("users").doc(fromUid).get(),
      ]);
      const recipientData = recipientSnap.data() || {};
      const tokens = Array.isArray(recipientData.fcmTokens) ?
          recipientData.fcmTokens.filter((t) => typeof t === "string") :
          [];
      if (tokens.length === 0) {
        logger.info("No FCM tokens for recipient", {recipient});
        return;
      }

      const senderName = (senderSnap.data() || {}).name || "Someone";

      let title;
      let body;
      const data = {
        type: String(type),
        fromUid: String(fromUid),
        connectionId: String(connId),
      };

      if (type === "buzz") {
        const count = Number(msg.count) || 1;
        title = "Buzz!";
        body = count === 1 ?
            `${senderName} buzzed you.` :
            `${senderName} buzzed you ${count} times.`;
        data.count = String(count);
      } else if (type === "voice") {
        title = senderName;
        body = "🎤 Voice message";
      } else {
        // text
        title = senderName;
        const text = typeof msg.text === "string" ? msg.text : "";
        body = text.length > 120 ? `${text.slice(0, 117)}...` : text;
        if (!body) body = "New message";
      }

      const message = {
        tokens,
        notification: {title, body},
        data,
        android: {
          priority: "high",
          notification: {
            channelId: "buzz_notifications",
            defaultVibrateTimings: true,
            defaultSound: true,
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      logger.info("push sent", {
        type,
        recipient,
        success: response.successCount,
        failure: response.failureCount,
      });

      // Prune invalid tokens.
      const invalid = [];
      response.responses.forEach((r, i) => {
        if (!r.success) {
          const code = r.error && r.error.code;
          if (code === "messaging/invalid-registration-token" ||
              code === "messaging/registration-token-not-registered") {
            invalid.push(tokens[i]);
          }
        }
      });
      if (invalid.length > 0) {
        await db.collection("users").doc(recipient).update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid),
        });
      }
    },
);
