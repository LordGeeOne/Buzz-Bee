import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/message_preview.dart';
import 'user_cache.dart';

/// Handles user-to-user connections and related messaging.
///
/// Data model (multi-connection):
///   users/{uid}/requests/{fromUid}            # pending incoming requests
///   users/{uid}/notifications/{id}            # in-app notifications
///   connections/{connectionId}
///     users: [uidA, uidB]                     # always 2 (1:1 chat)
///     createdAt, lastActivity
///   connections/{connectionId}/messages/{id}
///     fromUid, type: 'text'|'buzz'|'voice', text?, timestamp
///
/// A user may participate in many connections at once. The connection id is
/// deterministic per pair, so accepting the same person twice is a no-op.
class ConnectionService {
  ConnectionService._();

  static final _fs = FirebaseFirestore.instance;

  static String? get myUid => FirebaseAuth.instance.currentUser?.uid;

  /// Deterministic connection id from two uids.
  static String connectionIdFor(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Stream of the current user's active connection (first match), or null.
  static Stream<DocumentSnapshot<Map<String, dynamic>>?> myConnectionStream() {
    final uid = myUid;
    if (uid == null) {
      return Stream<DocumentSnapshot<Map<String, dynamic>>?>.value(null);
    }
    return _fs
        .collection('connections')
        .where('users', arrayContains: uid)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : snap.docs.first);
  }

  /// Stream of all the current user's active connections.
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  myConnectionsStream() {
    final uid = myUid;
    if (uid == null) {
      return Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.value(
        const [],
      );
    }
    return _fs
        .collection('connections')
        .where('users', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs);
  }

  /// Stream of pending request count (used for red-dot badges).
  static Stream<int> pendingRequestsCountStream() {
    final uid = myUid;
    if (uid == null) return Stream<int>.value(0);
    return _fs
        .collection('users')
        .doc(uid)
        .collection('requests')
        .snapshots()
        .map((s) => s.size);
  }

  /// Best-effort lookup of a user's display name + avatar from their
  /// Firestore profile (the canonical source — `FirebaseAuth.displayName`
  /// is often empty in this app since usernames live in the user doc).
  /// Falls back to FirebaseAuth fields and finally to empty strings.
  static Future<({String name, String photo})> _identityFor(String uid) async {
    String name = '';
    String photo = '';
    try {
      final data = await UserCache.fetch(uid) ?? const <String, dynamic>{};
      name = (data['username'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        name = (data['displayName'] as String?)?.trim() ?? '';
      }
      photo = (data['photoURL'] as String?) ?? '';
    } catch (_) {}
    if (name.isEmpty || photo.isEmpty) {
      final me = FirebaseAuth.instance.currentUser;
      if (me != null && me.uid == uid) {
        if (name.isEmpty) name = me.displayName ?? '';
        if (photo.isEmpty) photo = me.photoURL ?? '';
      }
    }
    return (name: name, photo: photo);
  }

  /// Send a connect request to [toUid] and create a notification for them.
  ///
  /// Runs the existence checks (already-connected? already-sent? reverse
  /// liked us?) inside a single Firestore transaction so two users liking
  /// each other concurrently can't both end up with a pending request and
  /// no connection. Outcomes:
  ///   * already connected         → no-op
  ///   * already sent (idempotent) → no-op (no duplicate notification)
  ///   * reverse like exists       → connection is created in-line +
  ///                                 both pending requests deleted +
  ///                                 match notifications dispatched
  ///   * none of the above         → request doc + notification written
  static Future<void> sendRequest(String toUid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final fromUid = me.uid;
    if (fromUid == toUid) return;

    final myIdentity = await _identityFor(fromUid);
    final fromName = myIdentity.name;
    final fromPhoto = myIdentity.photo;

    final connId = connectionIdFor(fromUid, toUid);
    final connRef = _fs.collection('connections').doc(connId);
    final forwardReqRef = _fs
        .collection('users')
        .doc(toUid)
        .collection('requests')
        .doc(fromUid);
    final reverseReqRef = _fs
        .collection('users')
        .doc(fromUid)
        .collection('requests')
        .doc(toUid);

    // Outcome flag set inside the transaction; drives post-commit fan-out.
    String outcome = 'sent';
    await _fs.runTransaction((tx) async {
      final connSnap = await tx.get(connRef);
      if (connSnap.exists) {
        outcome = 'connected';
        return;
      }
      final reverseSnap = await tx.get(reverseReqRef);
      if (reverseSnap.exists) {
        // Mutual like — create the connection inline. Rules permit this
        // because the reverse request still exists at rule-eval time
        // (deletes inside the same txn aren't visible to rule eval).
        tx.set(connRef, {
          'users': [fromUid, toUid],
          'createdAt': FieldValue.serverTimestamp(),
          'lastActivity': FieldValue.serverTimestamp(),
          'sent': {fromUid: 0, toUid: 0},
          'unseen': {fromUid: 0, toUid: 0},
        });
        tx.delete(reverseReqRef);
        // Forward may not exist yet, but delete is safe either way.
        tx.delete(forwardReqRef);
        outcome = 'matched';
        return;
      }
      final forwardSnap = await tx.get(forwardReqRef);
      if (forwardSnap.exists) {
        outcome = 'duplicate';
        return;
      }
      tx.set(forwardReqRef, {
        'fromUid': fromUid,
        'fromName': fromName,
        'fromPhoto': fromPhoto,
        'timestamp': FieldValue.serverTimestamp(),
      });
      outcome = 'sent';
    });

    if (outcome == 'connected' || outcome == 'duplicate') return;

    if (outcome == 'matched') {
      await _writeMatchNotifications(
        meUid: fromUid,
        meName: fromName,
        mePhoto: fromPhoto,
        otherUid: toUid,
        connId: connId,
      );
      return;
    }

    // outcome == 'sent' → notify recipient.
    await _fs.collection('users').doc(toUid).collection('notifications').add({
      'type': 'request',
      'fromUid': fromUid,
      'fromName': fromName,
      'fromPhoto': fromPhoto,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Accept a request from [fromUid]. Creates the connection doc and
  /// deletes the pending request. Notifies the original sender.
  ///
  /// Multi-connection: a user can be in many connections at once. The
  /// connection id is deterministic per pair, so attempting to accept the
  /// same person twice is idempotent.
  ///
  /// Runs as a transaction that first reads the pending request doc, so the
  /// client can't mistakenly create a connection without an actual incoming
  /// request. (Firestore security rules enforce the same invariant on the
  /// server side.)
  static Future<void> acceptRequest(String fromUid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final myUidLocal = me.uid;

    final connId = connectionIdFor(myUidLocal, fromUid);
    final connRef = _fs.collection('connections').doc(connId);
    final reqRef = _fs
        .collection('users')
        .doc(myUidLocal)
        .collection('requests')
        .doc(fromUid);
    // The reverse-direction request can also exist if both users liked each
    // other concurrently. Always nuke it so a future disconnect doesn't
    // leave behind an orphan that auto-matches them again.
    final reverseReqRef = _fs
        .collection('users')
        .doc(fromUid)
        .collection('requests')
        .doc(myUidLocal);

    await _fs.runTransaction((tx) async {
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) {
        // Either the request was already accepted/rejected, or the caller is
        // trying to forge a connection. Either way, abort.
        throw StateError('No pending request from this user');
      }
      final connSnap = await tx.get(connRef);
      if (!connSnap.exists) {
        tx.set(connRef, {
          'users': [myUidLocal, fromUid],
          'createdAt': FieldValue.serverTimestamp(),
          'lastActivity': FieldValue.serverTimestamp(),
          'sent': {myUidLocal: 0, fromUid: 0},
          'unseen': {myUidLocal: 0, fromUid: 0},
        });
      }
      tx.delete(reqRef);
      // Safe even if the doc doesn't exist.
      tx.delete(reverseReqRef);
    });

    final myIdentity = await _identityFor(myUidLocal);
    await _writeMatchNotifications(
      meUid: myUidLocal,
      meName: myIdentity.name,
      mePhoto: myIdentity.photo,
      otherUid: fromUid,
      connId: connId,
    );
  }

  /// Write the two `match` notification docs that drive the in-app popup
  /// and the FCM push. The accepter's self-notification is tagged
  /// `skipPush: true` so the cloud function doesn't fan out a redundant
  /// system notification to the device that just tapped Like.
  static Future<void> _writeMatchNotifications({
    required String meUid,
    required String meName,
    required String mePhoto,
    required String otherUid,
    required String connId,
  }) async {
    final other = await _identityFor(otherUid);
    final batch = _fs.batch();
    // Notify the OTHER user (UserA, the original liker).
    batch.set(
      _fs.collection('users').doc(otherUid).collection('notifications').doc(),
      {
        'type': 'match',
        'fromUid': meUid,
        'fromName': meName,
        'fromPhoto': mePhoto,
        'connectionId': connId,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      },
    );
    // Self-notification for ME (the accepter) — drives the local popup but
    // suppresses the FCM push (we're already in the foreground).
    batch.set(
      _fs.collection('users').doc(meUid).collection('notifications').doc(),
      {
        'type': 'match',
        'fromUid': otherUid,
        'fromName': other.name,
        'fromPhoto': other.photo,
        'connectionId': connId,
        'read': false,
        'skipPush': true,
        'timestamp': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  /// Reject a request — deletes it.
  static Future<void> rejectRequest(String fromUid) async {
    final uid = myUid;
    if (uid == null) return;
    await _fs
        .collection('users')
        .doc(uid)
        .collection('requests')
        .doc(fromUid)
        .delete();
  }

  /// Disconnect from a specific connection by id. Deletes the connection doc
  /// and any leftover pending request docs in either direction so a future
  /// `sendRequest` from either side starts from a clean slate (prevents the
  /// "old like causes auto-match after reconnect" bug).
  static Future<void> disconnect(String connectionId) async {
    final uid = myUid;
    if (uid == null) return;
    final connRef = _fs.collection('connections').doc(connectionId);
    String? partner;
    try {
      final snap = await connRef.get();
      final users = ((snap.data()?['users'] as List?) ?? const [])
          .cast<String>();
      partner = users.firstWhere((u) => u != uid, orElse: () => '');
      if (partner.isEmpty) partner = null;
    } catch (_) {}

    final batch = _fs.batch();
    batch.delete(connRef);
    if (partner != null) {
      batch.delete(
        _fs.collection('users').doc(uid).collection('requests').doc(partner),
      );
      batch.delete(
        _fs.collection('users').doc(partner).collection('requests').doc(uid),
      );
    }
    await batch.commit();
  }

  /// Send a non-buzz message (e.g. text) in the given connection.
  static Future<void> sendMessage({
    required String connectionId,
    required String type,
    String? text,
    Map<String, dynamic>? replyTo,
  }) async {
    final uid = myUid;
    if (uid == null) return;
    final connRef = _fs.collection('connections').doc(connectionId);
    final batch = _fs.batch();
    batch.set(connRef.collection('messages').doc(), {
      'fromUid': uid,
      'type': type,
      if (text != null) 'text': text,
      if (replyTo != null) 'replyTo': replyTo,
      'timestamp': FieldValue.serverTimestamp(),
    });
    batch.update(connRef, {
      'lastActivity': FieldValue.serverTimestamp(),
      'lastMessage': MessagePreview.buildLastMessage(
        type: type,
        fromUid: uid,
        text: text,
      ),
    });
    await batch.commit();
  }

  /// Send a batched buzz of [count] taps in a single transaction.
  /// Also: increments my `sent` counter by [count], adds [count] to
  /// partner's `unseen` counter, resets partner's `sent` counter to 0
  /// (they've been responded to) and resets my `unseen` counter to 0.
  static Future<void> sendBuzz({
    required String connectionId,
    required int count,
  }) async {
    if (count <= 0) return;
    final uid = myUid;
    if (uid == null) return;
    final connRef = _fs.collection('connections').doc(connectionId);
    final msgRef = connRef.collection('messages').doc();

    await _fs.runTransaction((tx) async {
      final snap = await tx.get(connRef);
      final data = snap.data();
      if (data == null) return;
      final users = (data['users'] as List?)?.cast<String>() ?? const [];
      final partner = users.firstWhere((u) => u != uid, orElse: () => '');
      if (partner.isEmpty) return;
      final sent = Map<String, dynamic>.from(
        (data['sent'] as Map?) ?? const {},
      );
      final unseen = Map<String, dynamic>.from(
        (data['unseen'] as Map?) ?? const {},
      );
      final mySent = ((sent[uid] as num?) ?? 0).toInt();
      final partnerUnseen = ((unseen[partner] as num?) ?? 0).toInt();

      tx.set(msgRef, {
        'fromUid': uid,
        'type': 'buzz',
        'count': count,
        'timestamp': FieldValue.serverTimestamp(),
      });
      tx.update(connRef, {
        'lastActivity': FieldValue.serverTimestamp(),
        'lastMessage': MessagePreview.buildLastMessage(
          type: 'buzz',
          fromUid: uid,
          count: count,
        ),
        'sent.$uid': mySent + count,
        'sent.$partner': 0,
        'unseen.$partner': partnerUnseen + count,
        'unseen.$uid': 0,
      });
    });
  }

  /// Called when the user opens the Buzz Buzz screen: zero out MY unseen
  /// counter on the connection doc (dashboard badge). Does not touch `sent`.
  static Future<void> markBuzzScreenOpened(String connectionId) async {
    final uid = myUid;
    if (uid == null) return;
    await _fs.collection('connections').doc(connectionId).update({
      'unseen.$uid': 0,
    });
  }

  /// Mark the current user as actively viewing this connection's chat.
  /// The Cloud Function reads this flag and skips push notifications when
  /// the recipient already has the chat open.
  static Future<void> setViewing(String connectionId, bool viewing) async {
    final uid = myUid;
    if (uid == null) return;
    try {
      await _fs.collection('connections').doc(connectionId).update({
        'viewing.$uid': viewing,
      });
    } catch (_) {
      // Best-effort; don't crash the UI if offline.
    }
  }

  /// Stream messages for a connection (oldest first).
  static Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(
    String connectionId,
  ) {
    return _fs
        .collection('connections')
        .doc(connectionId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(50)
        .snapshots();
  }
}
