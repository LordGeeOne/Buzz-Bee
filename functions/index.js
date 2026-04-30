/**
 * Cloud Functions for Buzz Bee.
 *
 * Listens for new messages in any connection's messages subcollection and
 * multicasts an FCM push notification to the recipient — but only when the
 * recipient is NOT currently viewing the chat (per `viewing.{uid}` flag on
 * the connection doc, which the Flutter ChatScreen toggles).
 */

const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
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

/**
 * Voice-call invite: when a new call doc is created with state=='ringing',
 * push a high-priority data-only FCM message to the callee. The Flutter
 * client uses this to show the Android ConnectionService incoming-call UI.
 */
exports.onCallCreated = onDocumentCreated(
    "connections/{connId}/calls/{callId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const call = snap.data() || {};
      if (call.state !== "ringing") return;

      const callerUid = call.callerUid;
      const calleeUid = call.calleeUid;
      const callId = call.callId || event.params.callId;
      const connId = event.params.connId;
      if (!callerUid || !calleeUid || !callId) return;

      const [calleeSnap, callerSnap] = await Promise.all([
        db.collection("users").doc(calleeUid).get(),
        db.collection("users").doc(callerUid).get(),
      ]);
      const tokens = (calleeSnap.data() || {}).fcmTokens || [];
      if (!Array.isArray(tokens) || tokens.length === 0) {
        logger.info("No FCM tokens for callee", {calleeUid});
        return;
      }
      const callerName = (callerSnap.data() || {}).name || "Someone";

      const message = {
        tokens: tokens.filter((t) => typeof t === "string"),
        data: {
          type: "call_invite",
          callId: String(callId),
          connectionId: String(connId),
          callerUid: String(callerUid),
          callerName: String(callerName),
        },
        android: {
          priority: "high",
          ttl: 30 * 1000,
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      logger.info("call invite sent", {
        callId,
        calleeUid,
        success: response.successCount,
        failure: response.failureCount,
      });
    },
);

/**
 * Voice-call cancel: when a ringing call is declined / ended / missed by
 * either side, push a data-only cancel message so the other device
 * dismisses its ConnectionService incoming-call UI.
 */
exports.onCallStateChanged = onDocumentUpdated(
    "connections/{connId}/calls/{callId}",
    async (event) => {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      if (before.state === after.state) return;
      const terminal = ["ended", "declined", "missed", "failed"];
      if (!terminal.includes(after.state)) return;

      const callerUid = after.callerUid;
      const calleeUid = after.calleeUid;
      const callId = after.callId || event.params.callId;
      const connId = event.params.connId;
      if (!callerUid || !calleeUid || !callId) return;

      // Notify the callee to dismiss the incoming-call UI if it was still
      // ringing. (The caller's UI is driven directly by the Firestore doc.)
      const calleeSnap = await db.collection("users").doc(calleeUid).get();
      const tokens = (calleeSnap.data() || {}).fcmTokens || [];
      if (!Array.isArray(tokens) || tokens.length === 0) return;

      const message = {
        tokens: tokens.filter((t) => typeof t === "string"),
        data: {
          type: "call_cancel",
          callId: String(callId),
          connectionId: String(connId),
          state: String(after.state),
        },
        android: {priority: "high", ttl: 30 * 1000},
      };
      const response = await admin.messaging().sendEachForMulticast(message);
      logger.info("call cancel sent", {
        callId,
        success: response.successCount,
        failure: response.failureCount,
      });
    },
);
