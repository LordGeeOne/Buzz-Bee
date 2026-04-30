import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../main.dart' show navigatorKey;
import '../screens/call_screen.dart';
import 'call_service.dart';

/// Wraps `flutter_callkit_incoming` so the rest of the app can show / cancel
/// the system Android ConnectionService incoming-call UI without touching the
/// plugin directly.
///
/// Routes user actions (accept / decline / end) into [CallService].
class CallkitService {
  CallkitService._();
  static final CallkitService instance = CallkitService._();

  bool _started = false;
  StreamSubscription<dynamic>? _eventSub;

  /// True while the splash should bypass animation and route directly to
  /// the call screen because the app cold-launched from a lock-screen
  /// accept tap.
  final ValueNotifier<PendingCall?> pendingIncoming =
      ValueNotifier<PendingCall?>(null);

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _eventSub = FlutterCallkitIncoming.onEvent.listen(_onEvent);

    // Cold-launch: the user tapped Accept on the lock screen before the
    // Flutter engine was alive. The plugin keeps the accepted call in
    // its active list — surface it so we can fast-path past the splash.
    await _checkColdLaunchAccept();
  }

  Future<void> _checkColdLaunchAccept() async {
    try {
      final dynamic active = await FlutterCallkitIncoming.activeCalls();
      if (active is! List || active.isEmpty) return;
      final first = active.first;
      if (first is! Map) return;
      final extra = (first['extra'] as Map?) ?? const {};
      final callId = extra['callId'] as String? ?? first['id'] as String?;
      final connectionId = extra['connectionId'] as String?;
      final callerUid = extra['callerUid'] as String?;
      final callerName = extra['callerName'] as String? ?? '';
      if (callId == null || connectionId == null || callerUid == null) {
        return;
      }
      pendingIncoming.value = PendingCall(
        callId: callId,
        connectionId: connectionId,
        callerUid: callerUid,
        callerName: callerName,
      );
      // Begin answering immediately so signaling progresses while the
      // navigator finishes booting.
      unawaited(
        CallService.instance.answerCall(
          callId: callId,
          connectionId: connectionId,
          callerName: callerName,
        ),
      );
    } catch (_) {}
  }

  /// Push the call screen using the global navigator. Retries on the next
  /// frame until the navigator is mounted (handles cold launch where the
  /// engine is alive but `MaterialApp` hasn't built yet).
  void pushCallScreen({
    required String callId,
    required String connectionId,
    required String peerUid,
    required String peerName,
  }) {
    var attempts = 0;
    void tryPush() {
      final nav = navigatorKey.currentState;
      if (nav == null) {
        if (++attempts > 200) return; // ~10s max
        Future.delayed(const Duration(milliseconds: 50), tryPush);
        return;
      }
      pendingIncoming.value = null;
      nav.push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            callId: callId,
            connectionId: connectionId,
            peerUid: peerUid,
            peerName: peerName,
            isIncoming: true,
          ),
        ),
      );
    }

    tryPush();
  }

  /// Show an incoming call UI from a received FCM data message.
  Future<void> showIncoming({
    required String callId,
    required String connectionId,
    required String callerUid,
    required String callerName,
    String callerAvatar = '',
  }) async {
    final displayName = callerName.isEmpty ? 'Buzz Bee' : callerName;
    final params = CallKitParams(
      id: callId,
      nameCaller: displayName,
      appName: 'Buzz Bee',
      avatar: callerAvatar,
      handle: 'Buzz Bee voice call',
      type: 0, // 0 = audio, 1 = video
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed Buzz Bee call',
        callbackText: 'Call back',
      ),
      extra: {
        'callId': callId,
        'connectionId': connectionId,
        'callerUid': callerUid,
        'callerName': callerName,
        'callerAvatar': callerAvatar,
      },
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        // Buzz Bee brand: warm honey-yellow gradient base + green accept.
        backgroundColor: '#1F1B16',
        backgroundUrl: callerAvatar,
        actionColor: '#FFC83D',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Dismiss any incoming-call UI for [callId] (e.g. caller cancelled).
  Future<void> endIncoming(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {}
  }

  Future<void> endAll() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  // ── Internals ──

  Future<void> _onEvent(dynamic event) async {
    if (event is! CallEvent) return;
    final body = (event.body as Map?) ?? const {};
    final extra = (body['extra'] as Map?) ?? const {};
    final callId = extra['callId'] as String? ?? body['id'] as String?;
    final connectionId = extra['connectionId'] as String?;
    final callerUid = extra['callerUid'] as String?;
    final callerName = extra['callerName'] as String? ?? '';
    if (callId == null || connectionId == null || callerUid == null) return;

    switch (event.event) {
      case Event.actionCallAccept:
        await CallService.instance.answerCall(
          callId: callId,
          connectionId: connectionId,
          callerName: callerName,
        );
        pushCallScreen(
          callId: callId,
          connectionId: connectionId,
          peerUid: callerUid,
          peerName: callerName,
        );
        break;
      case Event.actionCallDecline:
        await CallService.instance.declineCall(
          callId: callId,
          connectionId: connectionId,
        );
        break;
      case Event.actionCallTimeout:
        await CallService.instance.declineCall(
          callId: callId,
          connectionId: connectionId,
        );
        break;
      case Event.actionCallEnded:
      case Event.actionCallCallback:
        await CallService.instance.endCall();
        break;
      default:
        break;
    }
  }
}

class PendingCall {
  final String callId;
  final String connectionId;
  final String callerUid;
  final String callerName;
  PendingCall({
    required this.callId,
    required this.connectionId,
    required this.callerUid,
    required this.callerName,
  });
}
