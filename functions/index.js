/**
 * Cloud Functions for Buzz Bee.
 *
 * Listens for new messages in any connection's messages subcollection and
 * multicasts an FCM push notification to the recipient — but only when the
 * recipient is NOT currently viewing the chat (per `viewing.{uid}` flag on
 * the connection doc, which the Flutter ChatScreen toggles).
 */

const {onDocumentCreated, onDocumentUpdated, onDocumentDeleted} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

/**
 * Idempotency guard. Cloud Functions v2 / Eventarc has at-least-once
 * delivery, so the same event may fire more than once on retries. We dedupe
 * by event.id: the first invocation creates a marker doc, subsequent
 * invocations fail the create and short-circuit.
 *
 * Markers are short-lived; consider a scheduled cleanup job or Firestore
 * TTL policy on `processed_events` keyed on `createdAt`.
 *
 * Returns true if this invocation should proceed, false to skip.
 */
async function claimEvent(eventId) {
  if (!eventId) return true;
  const ref = db.collection("processed_events").doc(eventId);
  try {
    await ref.create({createdAt: admin.firestore.FieldValue.serverTimestamp()});
    return true;
  } catch (e) {
    // ALREADY_EXISTS — another invocation already handled this event.
    logger.info("duplicate event skipped", {eventId});
    return false;
  }
}

/**
 * Recursively delete every document under [ref] (a CollectionReference)
 * in batches of 200. Used by the connection-cleanup trigger.
 */
async function deleteCollection(ref) {
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await ref.limit(200).get();
    if (snap.empty) return;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    if (snap.size < 200) return;
  }
}

/**
 * Match push: when a `match`-type notification doc lands in any user's
 * notifications subcollection, fan out an FCM push so they hear about it
 * even if their app is backgrounded / closed. The Flutter foreground
 * `MatchOverlay` shows the in-app celebration popup separately when the
 * app is open, so this push is mainly to wake up the *other* user (the
 * original liker who hasn't opened the app yet).
 */
exports.onMatchNotificationCreated = onDocumentCreated(
    "users/{userId}/notifications/{notifId}",
    async (event) => {
      if (!(await claimEvent(event.id))) return;
      const snap = event.data;
      if (!snap) return;
      const notif = snap.data() || {};
      if (notif.type !== "match") return;
      if (notif.skipPush === true) {
        logger.info("match notif marked skipPush; not sending FCM");
        return;
      }

      const userId = event.params.userId;
      const fromName = (notif.fromName || "").toString().trim() || "Someone";
      const connectionId = (notif.connectionId || "").toString();
      const fromUid = (notif.fromUid || "").toString();

      const userSnap = await db.collection("users").doc(userId).get();
      const tokens = (userSnap.data() || {}).fcmTokens || [];
      const filtered = Array.isArray(tokens) ?
          tokens.filter((t) => typeof t === "string") :
          [];
      if (filtered.length === 0) {
        logger.info("No FCM tokens for match recipient", {userId});
        return;
      }

      const title = "It's a date!";
      const body = `You and ${fromName} sparked each other`;
      const data = {
        type: "match",
        connectionId: connectionId,
        fromUid: fromUid,
        fromName: fromName,
      };
      const message = {
        tokens: filtered,
        notification: {title, body},
        data,
        android: {
          priority: "high",
          collapseKey: `match_${connectionId || fromUid}`,
          notification: {
            channelId: "buzz_messages_v1",
            tag: `match_${connectionId || fromUid}`,
            color: "#6C63FF",
            notificationPriority: "PRIORITY_HIGH",
            visibility: "PRIVATE",
            defaultVibrateTimings: true,
            defaultSound: true,
          },
        },
        apns: {
          headers: {
            "apns-collapse-id": `match_${connectionId || fromUid}`,
          },
          payload: {
            aps: {
              alert: {title, body},
              sound: "default",
              "thread-id": `match_${connectionId || fromUid}`,
            },
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      logger.info("match push sent", {
        userId,
        success: response.successCount,
        failure: response.failureCount,
      });

      const invalid = [];
      response.responses.forEach((r, i) => {
        if (!r.success) {
          const code = r.error && r.error.code;
          if (code === "messaging/invalid-registration-token" ||
              code === "messaging/registration-token-not-registered") {
            invalid.push(filtered[i]);
          }
        }
      });
      if (invalid.length > 0) {
        await db.collection("users").doc(userId).update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid),
        });
      }
    },
);

exports.onBuzzMessageCreated = onDocumentCreated(
    "connections/{connId}/messages/{msgId}",
    async (event) => {
      if (!(await claimEvent(event.id))) return;
      const snap = event.data;
      if (!snap) return;
      const msg = snap.data() || {};
      const type = msg.type;
      if (type !== "buzz" && type !== "text" && type !== "voice") return;

      // Two-phase voice writes: skip until upload completes.
      if (type === "voice" && msg.uploading === true) return;

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
        title = senderName;
        body = count === 1 ?
            "Sent you a buzz" :
            `Sent you ${count} buzzes`;
        data.count = String(count);
      } else if (type === "voice") {
        title = senderName;
        body = "Voice message";
      } else {
        // text
        title = senderName;
        const text = typeof msg.text === "string" ? msg.text : "";
        body = text.length > 120 ? `${text.slice(0, 117)}...` : text;
        if (!body) body = "New message";
      }

      // Group / bundle notifications: a stable tag per (conversation, type)
      // means each new buzz / chat / voice from the same conversation
      // REPLACES the previous one in the system tray instead of stacking
      // up as separate entries. notificationCount surfaces the running
      // total on supported launchers.
      // WhatsApp-style grouping. Each message keeps its OWN notification
      // (unique tag = message id) so the tray shows the full history.
      // Android auto-bundles 4+ notifications from the same app into an
      // expandable group; collapseKey is set to the conversation id so the
      // *transport* (FCM) collapses bursts while offline, but the displayed
      // notifications themselves stay distinct once delivered.
      const msgId = event.params.msgId;
      const androidNotification = {
        channelId: "buzz_messages_v1",
        tag: msgId,
        color: "#6C63FF",
        notificationPriority: "PRIORITY_HIGH",
        visibility: "PRIVATE",
        defaultVibrateTimings: true,
        defaultSound: true,
      };

      const message = {
        tokens,
        notification: {title, body},
        data,
        android: {
          priority: "high",
          collapseKey: connId,
          notification: androidNotification,
        },
        apns: {
          headers: {
            "apns-collapse-id": connId,
          },
          payload: {
            aps: {
              alert: {title, body},
              sound: "default",
              "thread-id": connId,
            },
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
      if (!(await claimEvent(event.id))) return;
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
      if (!(await claimEvent(event.id))) return;
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

/**
 * Connection cleanup: when a connection doc is deleted (disconnect), recursively
 * delete its subcollections (messages, calls, callerCandidates, calleeCandidates)
 * to prevent storage bloat and stale data. Server-side so the client doesn't
 * need permission to enumerate large message histories.
 */
exports.onConnectionDeleted = onDocumentDeleted(
    "connections/{connId}",
    async (event) => {
      if (!(await claimEvent(event.id))) return;
      const connId = event.params.connId;
      const connRef = db.collection("connections").doc(connId);

      try {
        // Delete call ICE-candidate subcollections first, then their parent
        // call docs, then messages.
        const callsSnap = await connRef.collection("calls").get();
        for (const callDoc of callsSnap.docs) {
          await deleteCollection(callDoc.ref.collection("callerCandidates"));
          await deleteCollection(callDoc.ref.collection("calleeCandidates"));
        }
        await deleteCollection(connRef.collection("calls"));
        await deleteCollection(connRef.collection("messages"));
        logger.info("connection subcollections cleaned", {connId});
      } catch (e) {
        logger.error("connection cleanup failed", {connId, error: String(e)});
        throw e;
      }
    },
);

/**
 * Storage cleanup for ephemeral media. When a message doc is deleted (by
 * Firestore TTL on `expireAt`, by `onConnectionDeleted`, or manually), if
 * the message references a Storage object (voice / image), delete that
 * object too. Without this, TTL would silently leak Storage forever.
 *
 * Idempotent via claimEvent + ignore-if-not-found on the Storage call.
 */
exports.onMessageDeleted = onDocumentDeleted(
    "connections/{connId}/messages/{msgId}",
    async (event) => {
      if (!(await claimEvent(event.id))) return;
      const data = event.data && event.data.data();
      if (!data) return;
      const type = data.type;
      if (type !== "voice" && type !== "image") return;

      // Collect every Storage object referenced by the doc. Voice has a
      // single `storagePath`; image has `images: [{path, ...}]`. A "delete
      // for everyone" tombstone removed these eagerly, so we usually 404
      // here \u2014 that's expected and treated as success.
      const paths = [];
      if (typeof data.storagePath === "string" && data.storagePath) {
        paths.push(data.storagePath);
      }
      if (Array.isArray(data.images)) {
        for (const img of data.images) {
          if (img && typeof img.path === "string" && img.path) {
            paths.push(img.path);
          }
        }
      }
      if (paths.length === 0) return;

      const bucket = admin.storage().bucket();
      await Promise.all(paths.map(async (p) => {
        try {
          await bucket.file(p).delete();
          logger.info("ephemeral media deleted from storage", {path: p});
        } catch (e) {
          const code = e && e.code;
          if (code === 404) return;
          logger.warn("storage delete failed", {path: p, error: String(e)});
        }
      }));
    },
);
