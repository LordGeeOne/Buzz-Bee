import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// Lightweight presence tracking via a periodic Firestore heartbeat.
///
/// Writes `online: true` + `lastSeen` to `users/{uid}` every [_beatInterval]
/// while the app is foregrounded. On pause/detach (or [stop]) writes
/// `online: false` once. Readers treat the user as online if `online == true`
/// AND `lastSeen` is within [_staleAfter].
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  static const Duration _beatInterval = Duration(seconds: 30);
  static const Duration staleAfter = Duration(seconds: 60);

  Timer? _timer;
  bool _started = false;

  /// Begin tracking presence. Safe to call multiple times.
  void start() {
    if (_started) {
      _beat(true);
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _beat(true);
    _timer = Timer.periodic(_beatInterval, (_) => _beat(true));
  }

  /// Stop tracking and mark offline.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
    await _beat(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _beat(true);
        _timer ??= Timer.periodic(_beatInterval, (_) => _beat(true));
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
        _beat(false);
        break;
    }
  }

  Future<void> _beat(bool online) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Silent: presence is best-effort.
    }
  }

  /// Stream another user's online state. Emits `true` only when the remote
  /// flag is set AND the heartbeat is fresh enough.
  static Stream<bool> watchOnline(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) {
          final data = snap.data();
          if (data == null) return false;
          if (data['online'] != true) return false;
          final ts = data['lastSeen'];
          if (ts is! Timestamp) return false;
          final age = DateTime.now().difference(ts.toDate());
          return age < staleAfter;
        });
  }
}
