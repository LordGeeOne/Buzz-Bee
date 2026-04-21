import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles user-to-user connections and related messaging.
///
/// Data model (designed for future multi-connection / paid plans):
///   users/{uid}/requests/{fromUid}            # pending incoming requests
///   users/{uid}/notifications/{id}            # in-app notifications
///   connections/{connectionId}
///     users: [uidA, uidB]                     # always 2 for now
///     createdAt, lastActivity
///   connections/{connectionId}/messages/{id}
///     fromUid, type: 'text'|'buzz', text?, timestamp
///
/// Single-connection rule (free tier) is enforced by checking that neither
/// user already appears in another connection doc before accepting.
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

  /// Send a connect request to [toUid] and create a notification for them.
  static Future<void> sendRequest(String toUid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final fromUid = me.uid;
    final fromName = me.displayName ?? '';
    final fromPhoto = me.photoURL ?? '';

    await _fs
        .collection('users')
        .doc(toUid)
        .collection('requests')
        .doc(fromUid)
        .set({
          'fromUid': fromUid,
          'fromName': fromName,
          'fromPhoto': fromPhoto,
          'timestamp': FieldValue.serverTimestamp(),
        });

    await _fs.collection('users').doc(toUid).collection('notifications').add({
      'type': 'request',
      'fromUid': fromUid,
      'fromName': fromName,
      'fromPhoto': fromPhoto,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Accept a request from [fromUid]. Creates the connection doc (only write
  /// needed) and deletes the pending request. Notifies the original sender.
  ///
  /// Throws StateError if either party already has an active connection.
  ///
  /// Connection state is mirrored on each user's profile doc as
  /// `connectionId`. This avoids needing a list query against `connections`
  /// filtered by another user's uid (which security rules forbid).
  static Future<void> acceptRequest(String fromUid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final myUidLocal = me.uid;

    // Check my own user doc first (allowed: I own it).
    final myDoc = await _fs.collection('users').doc(myUidLocal).get();
    final myConnId = (myDoc.data()?['connectionId'] as String?) ?? '';
    if (myConnId.isNotEmpty) {
      throw StateError('You are already connected to someone.');
    }

    // Check the other user's doc (allowed: any signed-in user can read users).
    final otherDoc = await _fs.collection('users').doc(fromUid).get();
    final otherConnId = (otherDoc.data()?['connectionId'] as String?) ?? '';
    if (otherConnId.isNotEmpty) {
      throw StateError('That user is already connected to someone else.');
    }

    final connId = connectionIdFor(myUidLocal, fromUid);
    final connRef = _fs.collection('connections').doc(connId);
    final reqRef = _fs
        .collection('users')
        .doc(myUidLocal)
        .collection('requests')
        .doc(fromUid);
    final myUserRef = _fs.collection('users').doc(myUidLocal);
    final otherUserRef = _fs.collection('users').doc(fromUid);

    final batch = _fs.batch();
    batch.set(connRef, {
      'users': [myUidLocal, fromUid],
      'createdAt': FieldValue.serverTimestamp(),
      'lastActivity': FieldValue.serverTimestamp(),
      'sent': {myUidLocal: 0, fromUid: 0},
      'unseen': {myUidLocal: 0, fromUid: 0},
    });
    // Mirror connectionId on both user docs.
    batch.set(myUserRef, {'connectionId': connId}, SetOptions(merge: true));
    batch.set(otherUserRef, {'connectionId': connId}, SetOptions(merge: true));
    batch.delete(reqRef);
    await batch.commit();

    await _fs.collection('users').doc(fromUid).collection('notifications').add({
      'type': 'request_accepted',
      'fromUid': myUidLocal,
      'fromName': me.displayName ?? '',
      'fromPhoto': me.photoURL ?? '',
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
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

  /// Disconnect from current partner. Deletes the connection doc and clears
  /// `connectionId` on both user docs.
  static Future<void> disconnect() async {
    final uid = myUid;
    if (uid == null) return;
    final snap = await _fs
        .collection('connections')
        .where('users', arrayContains: uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return;
    final connDoc = snap.docs.first;
    final users = ((connDoc.data()['users'] as List?) ?? const [])
        .cast<String>();
    final partner = users.firstWhere((u) => u != uid, orElse: () => '');

    final batch = _fs.batch();
    batch.delete(connDoc.reference);
    batch.set(_fs.collection('users').doc(uid), {
      'connectionId': '',
    }, SetOptions(merge: true));
    if (partner.isNotEmpty) {
      batch.set(_fs.collection('users').doc(partner), {
        'connectionId': '',
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Send a non-buzz message (e.g. text) in the given connection.
  static Future<void> sendMessage({
    required String connectionId,
    required String type,
    String? text,
  }) async {
    final uid = myUid;
    if (uid == null) return;
    final connRef = _fs.collection('connections').doc(connectionId);
    final batch = _fs.batch();
    batch.set(connRef.collection('messages').doc(), {
      'fromUid': uid,
      'type': type,
      if (text != null) 'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    batch.update(connRef, {'lastActivity': FieldValue.serverTimestamp()});
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
