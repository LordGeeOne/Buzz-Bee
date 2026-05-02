import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/painting.dart';

/// Process-wide cache of user documents and avatar image providers so that
/// repeated mounts (e.g. dashboard tiles, chat header) render name + photo
/// synchronously instead of flashing through a loading state.
class UserCache {
  UserCache._();

  static final Map<String, Map<String, dynamic>> _data = {};
  static final Map<String, ImageProvider> _avatars = {};

  static Map<String, dynamic>? get(String uid) => _data[uid];

  static void put(String uid, Map<String, dynamic> data) {
    _data[uid] = data;
  }

  static ImageProvider avatarFor(String url) {
    return _avatars.putIfAbsent(url, () => NetworkImage(url));
  }

  /// Returns cached data immediately if present; otherwise fetches and caches.
  static Future<Map<String, dynamic>?> fetch(String uid) async {
    final cached = _data[uid];
    if (cached != null) return cached;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final d = snap.data();
    if (d != null) _data[uid] = d;
    return d;
  }
}
