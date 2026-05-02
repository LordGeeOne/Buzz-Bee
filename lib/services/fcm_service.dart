import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';
import 'callkit_service.dart';

/// Top-level background handler. Must be a top-level / static function and
/// annotated as a vm:entry-point so it survives the isolate split.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _routeData(message.data);
}

Future<void> _routeData(Map<String, dynamic> data) async {
  final type = data['type'];
  if (type == 'call_invite') {
    final callId = data['callId'] as String?;
    final connectionId = data['connectionId'] as String?;
    final callerUid = data['callerUid'] as String?;
    final callerName = data['callerName'] as String? ?? 'Buzz Bee';
    if (callId == null || connectionId == null || callerUid == null) return;
    await CallkitService.instance.start();
    await CallkitService.instance.showIncoming(
      callId: callId,
      connectionId: connectionId,
      callerUid: callerUid,
      callerName: callerName,
    );
  } else if (type == 'call_cancel') {
    final callId = data['callId'] as String?;
    if (callId == null) return;
    await CallkitService.instance.start();
    await CallkitService.instance.endIncoming(callId);
  }
}

/// Handles FCM token registration and foreground buzz vibration.
///
/// Tokens are stored in `users/{uid}.fcmTokens` as an array. A Cloud
/// Function reads this to multicast buzz push notifications to the
/// recipient when the app is backgrounded or killed.
///
/// Foreground buzzes are NOT vibrated here — the [ChatScreen] handles
/// vibration via the per-connection messages stream to avoid double-firing.
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

    // iOS only. Show the banner + sound even when the app is foreground
    // — the recipient may be on a different screen than the chat. The
    // Cloud Function already suppresses the push when the recipient is
    // actively viewing this chat (via the `viewing.{uid}` flag), so this
    // never double-fires while the conversation is open.
    await _fm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Register the background isolate handler for call invites that arrive
    // when the app is killed or in the background.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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

    // Foreground messages: route call data messages through CallkitService;
    // for buzz/text/voice fire a noticeable haptic pattern so the user
    // feels the incoming message even when the app is open on a different
    // screen than the conversation.
    FirebaseMessaging.onMessage.listen((message) async {
      final type = message.data['type'];
      if (type == 'call_invite' || type == 'call_cancel') {
        await _routeData(message.data);
        return;
      }
      await _foregroundBuzz(type);
    });
  }

  /// Two short pulses for chat / voice, three for a buzz. Uses
  /// HapticFeedback so we don't pull in another vibration plugin.
  Future<void> _foregroundBuzz(String? type) async {
    final pulses = type == 'buzz' ? 3 : 2;
    for (var i = 0; i < pulses; i++) {
      HapticFeedback.vibrate();
      if (i < pulses - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
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
