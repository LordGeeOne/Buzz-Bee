import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/message_preview.dart';

/// Hard cap on images per `type: 'image'` message. Mirrors the gallery cap
/// in the profile sheet so users get the same mental model.
const int kImagesPerMessage = 4;

/// Compressed bytes a single image is allowed to take. Above this we apply
/// progressively more aggressive compression. ~250 KB ends up around the
/// "Instagram DM" sweet-spot \u2014 sharp on phones, cheap to store.
const int _targetBytes = 250 * 1024;

/// Result of a single uploaded image. The path is the Storage object key
/// (used by the cleanup CF on delete) and the URL is the long-lived
/// download URL (used by the renderer).
class UploadedImage {
  final String path;
  final String url;
  final int width;
  final int height;
  final int size;
  const UploadedImage({
    required this.path,
    required this.url,
    required this.width,
    required this.height,
    required this.size,
  });

  Map<String, dynamic> toMap() => {
    'path': path,
    'url': url,
    'w': width,
    'h': height,
    'size': size,
  };
}

/// Compresses a single picked image and returns the on-disk path of the
/// resulting JPEG plus its decoded dimensions. Returns null if the source
/// can't be decoded.
Future<({String path, int width, int height, int size})?> _compressOne(
  XFile picked,
) async {
  final tmp = await getTemporaryDirectory();
  // Use the picked filename as the seed so two pickers in the same ms
  // don't collide. Always emit JPEG \u2014 smaller than PNG, and Storage
  // doesn't care about filename extension once contentType is set.
  final outPath =
      '${tmp.path}/img_${DateTime.now().microsecondsSinceEpoch}_${picked.name.hashCode}.jpg';

  // Two-pass: try q=80 first; if still over budget, drop to q=65.
  XFile? compressed = await FlutterImageCompress.compressAndGetFile(
    picked.path,
    outPath,
    quality: 80,
    minWidth: 1600,
    minHeight: 1600,
    keepExif: false,
    format: CompressFormat.jpeg,
  );
  if (compressed == null) return null;

  var bytes = await compressed.length();
  if (bytes > _targetBytes * 2) {
    // Re-encode at lower quality, overwriting the same file.
    compressed = await FlutterImageCompress.compressAndGetFile(
      compressed.path,
      outPath,
      quality: 65,
      minWidth: 1280,
      minHeight: 1280,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    if (compressed == null) return null;
    bytes = await compressed.length();
  }

  // Decode dimensions from the compressed JPEG via Flutter's image codec.
  final fileBytes = await File(compressed.path).readAsBytes();
  final codec = await ui.instantiateImageCodec(fileBytes);
  final frame = await codec.getNextFrame();
  final w = frame.image.width;
  final h = frame.image.height;
  frame.image.dispose();

  return (path: compressed.path, width: w, height: h, size: bytes);
}

/// Compress + upload up to [kImagesPerMessage] images and write a single
/// `type: 'image'` message doc. Mirrors the two-phase pattern used for
/// voice (placeholder doc \u2192 uploads \u2192 final update) so a crash
/// mid-upload never leaves an orphan Storage object.
///
/// [onMessageId] fires once the Firestore doc id is reserved so the UI
/// can deduplicate the local placeholder against the incoming snapshot.
Future<({String messageId, List<UploadedImage> images})> sendImageMessage({
  required String connectionId,
  required List<XFile> picked,
  void Function(String messageId)? onMessageId,
  Map<String, dynamic>? replyTo,
}) async {
  if (picked.isEmpty) {
    throw ArgumentError('sendImageMessage called with no images');
  }
  if (picked.length > kImagesPerMessage) {
    picked = picked.take(kImagesPerMessage).toList();
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('Not signed in');
  final fs = FirebaseFirestore.instance;
  final connRef = fs.collection('connections').doc(connectionId);

  final connSnap = await connRef.get();
  if (!connSnap.exists) {
    throw StateError('Connection doc does not exist: $connectionId');
  }
  final users = ((connSnap.data()?['users'] as List?) ?? const [])
      .cast<String>();
  if (!users.contains(uid)) {
    throw StateError('Caller $uid not in connection users $users');
  }

  final msgRef = connRef.collection('messages').doc();
  onMessageId?.call(msgRef.id);

  // Phase 1: write placeholder doc so the recipient sees the new message
  // immediately (with `uploading: true`, which the chat list filters).
  await msgRef.set({
    'fromUid': uid,
    'type': 'image',
    'count': picked.length,
    'uploading': true,
    if (replyTo != null) 'replyTo': replyTo,
    'timestamp': FieldValue.serverTimestamp(),
  });

  // Compress + upload every image in parallel. Failures on a single image
  // bubble up and abort the whole send (the placeholder doc is then deleted
  // by the catch site in chat_screen).
  final compressed = await Future.wait(picked.map(_compressOne));
  final missing = compressed.where((c) => c == null).length;
  if (missing > 0) {
    throw StateError('Could not decode $missing image(s)');
  }
  final compressedNN = compressed
      .cast<({String path, int width, int height, int size})>();

  final storage = FirebaseStorage.instance;
  final uploads = await Future.wait(
    List.generate(compressedNN.length, (i) async {
      final c = compressedNN[i];
      final ref = storage.ref('images/$connectionId/${msgRef.id}_$i.jpg');
      final task = await ref.putFile(
        File(c.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      return UploadedImage(
        path: ref.fullPath,
        url: url,
        width: c.width,
        height: c.height,
        size: task.totalBytes,
      );
    }),
  );

  // Phase 2: swap in the real URLs and clear `uploading`.
  await msgRef.update({
    'images': uploads.map((u) => u.toMap()).toList(),
    'uploading': FieldValue.delete(),
  });
  await connRef.update({
    'lastActivity': FieldValue.serverTimestamp(),
    'lastMessage': MessagePreview.buildLastMessage(
      type: 'image',
      fromUid: uid,
      count: uploads.length,
    ),
  });

  // Best-effort: delete the local compressed temp files.
  for (final c in compressedNN) {
    try {
      await File(c.path).delete();
    } catch (e) {
      debugPrint('image temp delete failed: $e');
    }
  }

  return (messageId: msgRef.id, images: uploads);
}

/// Hard delete every Storage object referenced by an image message. Used
/// from the "delete for everyone" path so the bytes are gone before we
/// flip the doc to a tombstone (otherwise the URL would still resolve
/// briefly until Firestore TTL eventually triggers the cleanup CF).
///
/// Best-effort; errors are swallowed because the cleanup CF will retry.
Future<void> deleteImageObjects(List<dynamic> images) async {
  final storage = FirebaseStorage.instance;
  for (final entry in images) {
    if (entry is! Map) continue;
    final path = entry['path'];
    if (path is! String || path.isEmpty) continue;
    try {
      await storage.ref(path).delete();
    } catch (e) {
      debugPrint('image storage delete failed: $e');
    }
  }
}
