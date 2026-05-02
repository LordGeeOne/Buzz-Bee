import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Enforces single-device-per-account: every successful sign-in stamps a
/// random `deviceId` onto `users/{uid}.activeDeviceId`. Each running app
/// instance subscribes to its own user doc; if it sees a different device
/// id it signs itself out immediately. Matches the WhatsApp / Snapchat
/// behaviour where logging in on a new device kicks the previous one.
///
/// The local device id lives in SharedPreferences (`active_device_id`)
/// and is generated once per install. Reinstalling produces a fresh id,
/// which is fine — that login will simply kick whatever was there.
class DeviceSessionService {
  DeviceSessionService._();
  static final DeviceSessionService instance = DeviceSessionService._();

  static const _prefsKey = 'active_device_id';

  String? _localDeviceId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  /// Returns the persistent local device id, creating one on first call.
  Future<String> ensureLocalDeviceId() async {
    if (_localDeviceId != null) return _localDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_prefsKey, id);
    }
    _localDeviceId = id;
    return id;
  }

  /// Stamp this device as the active one for [uid]. Call from the
  /// sign-in flow right after `signInWithCredential` succeeds.
  Future<void> claimSession(String uid) async {
    final id = await ensureLocalDeviceId();
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'activeDeviceId': id,
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('claimSession failed: $e');
    }
  }

  /// Subscribe to the user doc; invoke [onKicked] if `activeDeviceId`
  /// no longer matches this device. Safe to call multiple times — the
  /// previous subscription is cancelled first.
  Future<void> watch(String uid, VoidCallback onKicked) async {
    await _docSub?.cancel();
    final myId = await ensureLocalDeviceId();
    _docSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          final activeId = snap.data()?['activeDeviceId'] as String?;
          // Null means the doc hasn't been stamped yet (e.g. brand-new
          // sign-in still in flight). Don't kick on null — only on a
          // confirmed mismatch.
          if (activeId == null || activeId.isEmpty) return;
          if (activeId != myId) onKicked();
        });
  }

  Future<void> stopWatch() async {
    await _docSub?.cancel();
    _docSub = null;
  }

  /// Sign out of Firebase + Google AND drop this device's FCM token so
  /// it stops receiving pushes. Used both for the "kicked" path and the
  /// user-initiated sign-out button.
  Future<void> signOut() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
                'fcmTokens': FieldValue.arrayRemove([token]),
              });
        }
        await FirebaseMessaging.instance.deleteToken();
      } catch (e) {
        debugPrint('FCM token cleanup failed: $e');
      }
    }
    await stopWatch();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }
}
