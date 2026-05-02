import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../utils/message_preview.dart';

/// Records short voice notes and uploads them to Firebase Storage,
/// then writes a `type: 'voice'` doc to the connection's messages.
///
/// Settings are tuned for tiny files (~3-4 KB/s):
///   * AAC-LC in m4a, 16 kHz mono, 24 kbps.
class VoiceRecorderService {
  VoiceRecorderService();

  static const Duration maxDuration = Duration(seconds: 20);

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  DateTime? _startedAt;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _ampSamples = [];

  /// Returns true if mic permission is granted (requesting if needed).
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Begin recording to a temp file. Returns the file path.
  Future<String?> start() async {
    if (await _recorder.isRecording()) return _currentPath;
    if (!await ensurePermission()) return null;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 24000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _currentPath = path;
    _startedAt = DateTime.now();
    _ampSamples.clear();
    _ampSub?.cancel();
    // Sample the mic level ~10x/s and normalize dBFS into 0..1.
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) {
          // a.current is in dBFS (negative; 0 = max). Map -45..0 dBFS -> 0..1.
          final db = a.current.isFinite ? a.current : -45.0;
          final clamped = db.clamp(-45.0, 0.0);
          final norm = ((clamped + 45.0) / 45.0).clamp(0.0, 1.0);
          _ampSamples.add(norm);
        });
    return path;
  }

  /// Stop and return the file path + duration + downsampled waveform.
  /// Returns null if discarded (too short or no active recording).
  Future<({String path, Duration duration, List<double> waveform})?> stop({
    Duration minDuration = const Duration(milliseconds: 300),
  }) async {
    if (!await _recorder.isRecording()) {
      await _ampSub?.cancel();
      _ampSub = null;
      _currentPath = null;
      _startedAt = null;
      return null;
    }
    final path = await _recorder.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    final started = _startedAt;
    final samples = List<double>.from(_ampSamples);
    _ampSamples.clear();
    _currentPath = null;
    _startedAt = null;
    if (path == null || started == null) return null;
    final duration = DateTime.now().difference(started);
    if (duration < minDuration) {
      try {
        await File(path).delete();
      } catch (_) {}
      return null;
    }
    final waveform = _downsample(samples, 40);
    return (path: path, duration: duration, waveform: waveform);
  }

  /// Downsample raw amplitude samples into [bucketCount] buckets (max-pooling).
  static List<double> _downsample(List<double> src, int bucketCount) {
    if (src.isEmpty) return List<double>.filled(bucketCount, 0.05);
    if (src.length <= bucketCount) {
      // Pad with the average so the bar count is stable.
      final out = List<double>.from(src);
      while (out.length < bucketCount) {
        out.add(out.isEmpty ? 0.05 : out.last);
      }
      return out;
    }
    final out = List<double>.filled(bucketCount, 0.0);
    final step = src.length / bucketCount;
    for (var i = 0; i < bucketCount; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).floor().clamp(start + 1, src.length);
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        if (src[j] > peak) peak = src[j];
      }
      out[i] = peak;
    }
    return out;
  }

  /// Stop without keeping the file (slide-to-cancel).
  Future<void> cancel() async {
    await _ampSub?.cancel();
    _ampSub = null;
    _ampSamples.clear();
    if (await _recorder.isRecording()) {
      final path = await _recorder.stop();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
    _currentPath = null;
    _startedAt = null;
  }

  Stream<Amplitude> amplitudeStream() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}

/// Uploads a recorded voice file to Storage and writes the message doc.
/// Returns the new message id and download URL so the UI can swap a
/// pending placeholder bubble into a real voice player without remounting.
///
/// [onMessageId] fires as soon as the Firestore doc id is reserved (before
/// upload). The UI uses this to claim the id on its placeholder so the
/// incoming Firestore snapshot doesn't render a duplicate bubble.
Future<({String messageId, String url})> sendVoiceMessage({
  required String connectionId,
  required String localPath,
  required Duration duration,
  List<double> waveform = const [],
  void Function(String messageId)? onMessageId,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('Not signed in');
  final fs = FirebaseFirestore.instance;
  final connRef = fs.collection('connections').doc(connectionId);

  // Sanity check: confirm the caller is actually in this connection's
  // `users` array. Storage rules require this; failing fast here gives
  // a clear error instead of an opaque 403.
  final connSnap = await connRef.get();
  final users = ((connSnap.data()?['users'] as List?) ?? const [])
      .cast<String>();
  // ignore: avoid_print
  print(
    '[voice] uid=$uid connId=$connectionId connExists=${connSnap.exists} users=$users',
  );
  if (!connSnap.exists) {
    throw StateError('Connection doc does not exist: $connectionId');
  }
  if (!users.contains(uid)) {
    throw StateError('Caller $uid not in connection users $users');
  }

  final msgRef = connRef.collection('messages').doc();
  onMessageId?.call(msgRef.id);
  final file = File(localPath);
  if (!await file.exists()) {
    throw StateError('Recording file missing: $localPath');
  }

  // Pre-seed the local playback cache BEFORE writing the Firestore doc.
  // That way, when the chat screen sees the new message, the cache file
  // already exists and the player can load it instantly from disk \u2014
  // no race against Storage CDN propagation.
  try {
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${supportDir.path}/voice_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final cachedFile = File('${cacheDir.path}/${msgRef.id}.m4a');
    await file.copy(cachedFile.path);
  } catch (e) {
    debugPrint('voice cache seed failed: $e');
  }

  // Two-phase write so we never orphan a Storage object on crash:
  //   Phase 1: write the message doc with `uploading: true` (no URL yet).
  //   Phase 2: upload to Storage, then update the doc with URL + size.
  // The Cloud Function ignores docs while `uploading == true`, so push
  // notifications only fire after the message is fully realized.
  await msgRef.set({
    'fromUid': uid,
    'type': 'voice',
    'duration': duration.inMilliseconds,
    'waveform': waveform,
    'uploading': true,
    'timestamp': FieldValue.serverTimestamp(),
  });

  final storageRef = FirebaseStorage.instance.ref(
    'voice/$connectionId/${msgRef.id}.m4a',
  );
  final task = await storageRef.putFile(
    file,
    SettableMetadata(contentType: 'audio/mp4'),
  );
  final url = await storageRef.getDownloadURL();
  await msgRef.update({
    'url': url,
    'storagePath': storageRef.fullPath,
    'size': task.totalBytes,
    'uploading': FieldValue.delete(),
  });
  await connRef.update({
    'lastActivity': FieldValue.serverTimestamp(),
    'lastMessage': MessagePreview.buildLastMessage(type: 'voice', fromUid: uid),
  });

  try {
    await file.delete();
  } catch (e) {
    debugPrint('voice temp file delete failed: $e');
  }

  return (messageId: msgRef.id, url: url);
}
