import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

/// Handles FCM token registration and foreground buzz vibration.
///
/// Tokens are stored in `users/{uid}.fcmTokens` as an array. A Cloud
/// Function reads this to multicast buzz push notifications to the
/// recipient when the app is backgrounded or killed.
///
/// Foreground buzzes are NOT vibrated here — [BuzzNotifier] handles
/// vibration via the Firestore `messages` stream to avoid double-firing.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final _fm = FirebaseMessaging.instance;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Ask for notification permission (Android 13+ requires runtime prompt
    // handled by the plugin).
    await _fm.requestPermission(alert: true, badge: true, sound: true);

    // Suppress heads-up when app is foreground: Firestore listener handles
    // vibration + the user can already see the state live.
    await _fm.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _registerToken(user.uid);
      }
    });

    _fm.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _saveToken(uid, token);
      }
    });

    // Foreground messages: vibrate just once; the Firestore listener covers
    // the batched pattern already. We still handle this for completeness
    // when the Firestore listener hasn't fired yet.
    FirebaseMessaging.onMessage.listen((_) {
      HapticFeedback.vibrate();
    });
  }

  Future<void> _registerToken(String uid) async {
    try {
      final token = await _fm.getToken();
      if (token != null) {
        await _saveToken(uid, token);
      }
    } catch (_) {
      // Ignore; we'll retry on token refresh.
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }
}
