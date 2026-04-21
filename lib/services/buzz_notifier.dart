import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import 'connection_service.dart';

/// App-wide buzz listener. While the user is signed in, listens to the current
/// connection's `messages` stream and vibrates on incoming buzz messages (from
/// the partner). Caps vibration at 5 pulses when count > 10.
///
/// The Buzz Buzz screen marks itself foreground via
/// [setBuzzScreenForeground] so this notifier does NOT double-fire while
/// that screen is active (the screen has its own haptic on tap).
class BuzzNotifier {
  BuzzNotifier._();
  static final BuzzNotifier instance = BuzzNotifier._();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>?>? _connSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _msgSub;
  String? _connectionId;
  DateTime? _msgsSubscribedAt;
  bool _buzzScreenForeground = false;

  void start() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      _resetConnectionSubs();
      if (user != null) {
        _connSub = ConnectionService.myConnectionStream().listen(
          _onConnChanged,
        );
      }
    });
  }

  void setBuzzScreenForeground(bool value) {
    _buzzScreenForeground = value;
  }

  void _resetConnectionSubs() {
    _connSub?.cancel();
    _connSub = null;
    _msgSub?.cancel();
    _msgSub = null;
    _connectionId = null;
  }

  void _onConnChanged(DocumentSnapshot<Map<String, dynamic>>? snap) {
    final connId = snap?.id;
    if (connId == _connectionId) return;
    _msgSub?.cancel();
    _msgSub = null;
    _connectionId = connId;
    if (connId == null || connId.isEmpty) return;
    _msgsSubscribedAt = DateTime.now();
    _msgSub = ConnectionService.messagesStream(
      connId,
    ).listen(_onMessagesChanged);
  }

  Future<void> _onMessagesChanged(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final subscribedAt = _msgsSubscribedAt;
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final data = change.doc.data();
      if (data == null) continue;
      if (data['type'] != 'buzz') continue;
      if (data['fromUid'] == myUid) continue;
      // Ignore historical buzzes delivered on initial snapshot load.
      final ts = data['timestamp'];
      if (ts is Timestamp &&
          subscribedAt != null &&
          ts.toDate().isBefore(subscribedAt)) {
        continue;
      }
      // Buzz screen handles its own haptic feedback on taps, but incoming
      // partner buzzes still deserve a vibration there too.
      if (_buzzScreenForeground) {
        // Keep it subtle on the buzz screen: single pulse regardless of count.
        HapticFeedback.vibrate();
        continue;
      }
      final count = ((data['count'] as num?) ?? 1).toInt();
      await _vibrateCount(count);
    }
  }

  Future<void> _vibrateCount(int count) async {
    final pulses = count > 10 ? 5 : count.clamp(1, 10);
    for (var i = 0; i < pulses; i++) {
      HapticFeedback.vibrate();
      if (i < pulses - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
  }
}
