import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Process-wide registry of [AudioPlayer]s keyed by message id.
///
/// Voice bubble widgets come and go as the chat list rebuilds, but the
/// players themselves live here so audio never reloads, restarts, or
/// re-downloads when a new message arrives.
class VoicePlayerRegistry {
  VoicePlayerRegistry._();
  static final VoicePlayerRegistry instance = VoicePlayerRegistry._();

  final Map<String, AudioPlayer> _players = {};
  final Map<String, Future<void>> _loading = {};
  String? _activeId;

  AudioPlayer playerFor(String messageId) {
    return _players.putIfAbsent(messageId, () => AudioPlayer());
  }

  /// Loads the audio source for [messageId] exactly once (per process).
  Future<void> ensureLoaded({required String messageId, required String url}) {
    return _loading.putIfAbsent(
      messageId,
      () => _load(messageId: messageId, url: url),
    );
  }

  Future<void> _load({required String messageId, required String url}) async {
    final player = playerFor(messageId);
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${supportDir.path}/voice_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final cacheFile = File('${cacheDir.path}/$messageId.m4a');
    try {
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        await player.setFilePath(cacheFile.path);
      } else {
        final source = LockCachingAudioSource(
          Uri.parse(url),
          cacheFile: cacheFile,
        );
        await player.setAudioSource(source);
      }
    } catch (e) {
      // Allow retry on next ensureLoaded call.
      _loading.remove(messageId);
      debugPrint('VoicePlayerRegistry load failed ($messageId): $e');
      rethrow;
    }
  }

  /// Pause all other players when one starts playing.
  void markActive(String messageId) {
    if (_activeId != null && _activeId != messageId) {
      _players[_activeId]?.pause();
    }
    _activeId = messageId;
  }

  /// Dispose every player. Call when leaving the chat screen for good.
  Future<void> disposeAll() async {
    for (final p in _players.values) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _players.clear();
    _loading.clear();
    _activeId = null;
  }
}
