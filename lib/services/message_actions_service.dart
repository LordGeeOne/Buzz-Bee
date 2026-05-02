import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/message_preview.dart';
import 'image_message_service.dart';

/// Server-side window during which a sender may edit or delete a message.
/// Mirrors WhatsApp / Telegram. Enforced both client-side (here) and in
/// Firestore security rules (the source of truth).
const Duration kMessageEditWindow = Duration(hours: 1);

/// Lifetime of a "deleted for everyone" tombstone before Firestore TTL
/// purges it. 24h is long enough that anyone scrolled into the chat
/// during the day still sees the "this message was deleted" placeholder.
const Duration _tombstoneTtl = Duration(hours: 24);

/// Maximum chars of original text we denormalize into the `replyTo` chip.
/// Keeps the doc tiny — bubbles only show one line anyway.
const int kReplyPreviewMaxLen = 80;

/// Build the small denormalized `replyTo` blob to attach to an outgoing
/// message. Truncates text to [kReplyPreviewMaxLen] and stores only what
/// the chip needs (no urls, no full text). Returns null for tombstones.
Map<String, dynamic>? buildReplyTo({
  required String messageId,
  required Map<String, dynamic> data,
}) {
  if (data['deletedAt'] != null) return null;
  final type = (data['type'] as String?) ?? 'text';
  final fromUid = (data['fromUid'] as String?) ?? '';
  String? preview;
  if (type == 'text') {
    final t = ((data['text'] as String?) ?? '').trim();
    if (t.isNotEmpty) {
      preview = t.length > kReplyPreviewMaxLen
          ? '${t.substring(0, kReplyPreviewMaxLen)}…'
          : t;
    }
  }
  return {
    'messageId': messageId,
    'fromUid': fromUid,
    'type': type,
    if (preview != null) 'preview': preview,
  };
}

/// Mutations to a single message doc: edit text, soft-delete, react.
/// Lives outside ConnectionService because these operations target a
/// specific message ref, not the connection.
class MessageActionsService {
  MessageActionsService._();

  /// True if [data] is editable/deletable by the current user. Cheap
  /// client-side guard so the long-press menu can hide the items;
  /// Firestore rules enforce the same window server-side.
  static bool canModify(Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || data['fromUid'] != uid) return false;
    if (data['deletedAt'] != null) return false;
    final ts = data['timestamp'];
    if (ts is! Timestamp) return false;
    final age = DateTime.now().difference(ts.toDate());
    return age < kMessageEditWindow;
  }

  /// True if [data] is an editable text message authored by the caller
  /// within the edit window.
  static bool canEdit(Map<String, dynamic> data) =>
      canModify(data) && data['type'] == 'text';

  /// Edit a text message. No-op if the new text is empty or unchanged.
  static Future<void> editText({
    required String connectionId,
    required String messageId,
    required String newText,
  }) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;
    final fs = FirebaseFirestore.instance;
    final ref = fs
        .collection('connections')
        .doc(connectionId)
        .collection('messages')
        .doc(messageId);
    await ref.update({
      'text': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
    });

    // If this is currently the last message on the connection, refresh the
    // dashboard preview so it reflects the edit. We do this by reading the
    // connection doc and only updating when the lastMessage is ours.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final connRef = fs.collection('connections').doc(connectionId);
    try {
      final snap = await connRef.get();
      final last = (snap.data()?['lastMessage'] as Map?)
          ?.cast<String, dynamic>();
      if (last != null && last['fromUid'] == uid && last['type'] == 'text') {
        await connRef.update({
          'lastMessage': MessagePreview.buildLastMessage(
            type: 'text',
            fromUid: uid,
            text: trimmed,
          ),
        });
      }
    } catch (e) {
      debugPrint('lastMessage refresh on edit failed: $e');
    }
  }

  /// Soft-delete: clear content, mark the doc as a tombstone, set
  /// [expireAt] so Firestore TTL eventually purges the doc (and via
  /// the cleanup CF, any leftover Storage object). For voice / image
  /// messages we also delete the Storage objects up front so the bytes
  /// are gone immediately.
  static Future<void> deleteForEveryone({
    required String connectionId,
    required String messageId,
    required Map<String, dynamic> data,
  }) async {
    final type = data['type'] as String?;
    // Delete Storage objects up front \u2014 the doc-level TTL would
    // eventually trigger cleanup, but we want the bytes gone now.
    if (type == 'voice') {
      final path = data['storagePath'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          // Use the same helper since it ignores 404s gracefully.
          await deleteImageObjects([
            {'path': path},
          ]);
        } catch (_) {}
      }
    } else if (type == 'image') {
      final imgs = (data['images'] as List?) ?? const [];
      await deleteImageObjects(imgs);
    }

    final fs = FirebaseFirestore.instance;
    final ref = fs
        .collection('connections')
        .doc(connectionId)
        .collection('messages')
        .doc(messageId);
    await ref.update({
      'deletedAt': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch + _tombstoneTtl.inMilliseconds,
      ),
      // Strip every payload field so the message carries no recoverable
      // content, even if a client cached the doc before deletion.
      'text': FieldValue.delete(),
      'images': FieldValue.delete(),
      'url': FieldValue.delete(),
      'storagePath': FieldValue.delete(),
      'waveform': FieldValue.delete(),
      'duration': FieldValue.delete(),
      'size': FieldValue.delete(),
    });

    // If this was the last preview on the connection, replace it with a
    // neutral "Message deleted" line so the dashboard isn't lying.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final connRef = fs.collection('connections').doc(connectionId);
    try {
      final snap = await connRef.get();
      final last = (snap.data()?['lastMessage'] as Map?)
          ?.cast<String, dynamic>();
      if (last != null && last['fromUid'] == uid) {
        await connRef.update({
          'lastMessage': MessagePreview.buildLastMessage(
            type: 'deleted',
            fromUid: uid,
          ),
        });
      }
    } catch (e) {
      debugPrint('lastMessage refresh on delete failed: $e');
    }
  }

  /// Toggle the caller's reaction. Passing null clears it.
  static Future<void> setReaction({
    required String connectionId,
    required String messageId,
    required String? emoji,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('connections')
        .doc(connectionId)
        .collection('messages')
        .doc(messageId);
    await ref.update({'reactions.$uid': emoji ?? FieldValue.delete()});
  }
}
