import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:just_audio/just_audio.dart';

import '../services/connection_service.dart';
import '../services/presence_service.dart';
import '../services/voice_player_registry.dart';
import '../services/voice_recorder_service.dart';
import '../theme/nexaryo_colors.dart';

/// Full-screen chat with a connected partner.
///
/// Streams `connections/{id}/messages` for text + buzz + voice messages,
/// sends text via [ConnectionService.sendMessage], and sends batched
/// buzzes via [ConnectionService.sendBuzz].
class ChatScreen extends StatefulWidget {
  final String partnerUid;

  const ChatScreen({super.key, required this.partnerUid});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const Duration _flushWindow = Duration(seconds: 5);

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();

  String? _connectionId;
  String? _partnerName;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _messagesStream;
  int _serverSent = 0;
  int _pendingCount = 0;
  Timer? _flushTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _connSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingSub;
  DateTime? _incomingSubscribedAt;

  // Live values consumed by the popup so it rebuilds in-place on tap/sync.
  final ValueNotifier<int> _displayCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> _connected = ValueNotifier<bool>(false);
  final ValueNotifier<List<int>> _sentLabels = ValueNotifier<List<int>>([]);
  int _sentKey = 0;

  // Voice recording / typing state.
  final ValueNotifier<bool> _hasText = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> _recordElapsed = ValueNotifier<Duration>(
    Duration.zero,
  );
  final VoiceRecorderService _voice = VoiceRecorderService();
  Timer? _recordTimer;
  bool _voiceCancelled = false;

  // Voice messages currently uploading. Rendered as placeholder bubbles
  // at the bottom of the list so the sender sees instant feedback while
  // the audio uploads + the Firestore doc round-trips back via the stream.
  final List<_PendingVoice> _pendingVoices = [];
  int _pendingVoiceSeq = 0;

  // Cache of parsed waveform arrays per messageId so we don't re-allocate
  // a `List<double>` on every Firestore snapshot.
  final Map<String, List<double>> _waveformCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputFocus.addListener(_onFocusChange);
    _textController.addListener(_onTextChanged);
    _bootstrap();
  }

  void _onTextChanged() {
    final has = _textController.text.trim().isNotEmpty;
    if (has != _hasText.value) _hasText.value = has;
  }

  Future<void> _bootstrap() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    final connId = ConnectionService.connectionIdFor(myUid, widget.partnerUid);
    _connectionId = connId;
    _messagesStream = ConnectionService.messagesStream(connId);

    final pSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.partnerUid)
        .get();
    if (!mounted) return;
    setState(() {
      _partnerName = pSnap.data()?['name'] as String?;
      _connected.value = true;
    });

    unawaited(ConnectionService.markBuzzScreenOpened(connId));
    unawaited(ConnectionService.setViewing(connId, true));

    _connSub = FirebaseFirestore.instance
        .collection('connections')
        .doc(connId)
        .snapshots()
        .listen(_onConnSnap);

    // Listen separately for incoming partner messages so we can vibrate.
    // The main StreamBuilder is for rendering; this one only fires haptics.
    _incomingSubscribedAt = DateTime.now();
    _incomingSub = ConnectionService.messagesStream(
      connId,
    ).listen(_onIncomingMessages);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final connId = _connectionId;
    if (connId != null && connId.isNotEmpty) {
      unawaited(ConnectionService.setViewing(connId, false));
    }
    _flushTimer?.cancel();
    _flushPending();
    _recordTimer?.cancel();
    _voice.dispose();
    VoicePlayerRegistry.instance.disposeAll();
    _connSub?.cancel();
    _incomingSub?.cancel();
    _inputFocus.removeListener(_onFocusChange);
    _inputFocus.dispose();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _displayCount.dispose();
    _connected.dispose();
    _sentLabels.dispose();
    _hasText.dispose();
    _isRecording.dispose();
    _recordElapsed.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final connId = _connectionId;
    if (state == AppLifecycleState.resumed) {
      if (connId != null && connId.isNotEmpty) {
        unawaited(ConnectionService.setViewing(connId, true));
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (connId != null && connId.isNotEmpty) {
        unawaited(ConnectionService.setViewing(connId, false));
      }
      _flushPending();
    }
  }

  void _onIncomingMessages(QuerySnapshot<Map<String, dynamic>> snap) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    final subscribedAt = _incomingSubscribedAt;
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final data = change.doc.data();
      if (data == null) continue;
      if (data['fromUid'] == myUid) continue;
      final type = data['type'] as String? ?? 'text';
      final ts = data['timestamp'];
      if (ts is Timestamp &&
          subscribedAt != null &&
          ts.toDate().isBefore(subscribedAt)) {
        continue;
      }
      if (type == 'buzz') {
        // Vibrate once per buzz tap, capped at 5 pulses.
        final count = ((data['count'] as num?) ?? 1).toInt();
        unawaited(_vibrateBuzz(count));
      } else if (type == 'text' || type == 'voice') {
        HapticFeedback.mediumImpact();
      }
    }
  }

  Future<void> _vibrateBuzz(int count) async {
    final pulses = count > 10 ? 5 : count.clamp(1, 10);
    for (var i = 0; i < pulses; i++) {
      HapticFeedback.vibrate();
      if (i < pulses - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
  }

  void _onConnSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final sentMap = (data['sent'] as Map?) ?? const {};
    final newServerSent = ((sentMap[myUid] as num?) ?? 0).toInt();
    if (newServerSent < _serverSent) {
      _pendingCount = 0;
      _flushTimer?.cancel();
    }
    _serverSent = newServerSent;
    _displayCount.value = _serverSent + _pendingCount;
  }

  void _onBuzzTap() {
    HapticFeedback.vibrate();
    _pendingCount++;
    _displayCount.value = _serverSent + _pendingCount;
    _sentLabels.value = [..._sentLabels.value, _sentKey++];
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushWindow, _flushPending);
  }

  void _removeSentLabel(int key) {
    _sentLabels.value = _sentLabels.value.where((k) => k != key).toList();
  }

  Future<void> _flushPending() async {
    final count = _pendingCount;
    final connId = _connectionId;
    if (count <= 0 || connId == null || connId.isEmpty) return;
    _pendingCount = 0;
    _flushTimer?.cancel();
    _flushTimer = null;
    try {
      await ConnectionService.sendBuzz(connectionId: connId, count: count);
    } catch (_) {
      // Silent.
    }
  }

  void _onFocusChange() {
    if (_inputFocus.hasFocus) {
      Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    final connId = _connectionId;
    if (text.isEmpty || connId == null || connId.isEmpty) return;
    _textController.clear();
    await ConnectionService.sendMessage(
      connectionId: connId,
      type: 'text',
      text: text,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // ── Voice recording ──
  Future<void> _startRecording() async {
    if (_isRecording.value) return;
    final connId = _connectionId;
    if (connId == null || connId.isEmpty) return;
    _voiceCancelled = false;
    final path = await _voice.start();
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
      return;
    }
    HapticFeedback.mediumImpact();
    _isRecording.value = true;
    _recordElapsed.value = Duration.zero;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final elapsed = _recordElapsed.value + const Duration(milliseconds: 100);
      _recordElapsed.value = elapsed;
      if (elapsed >= VoiceRecorderService.maxDuration) {
        _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording.value) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    _isRecording.value = false;
    final connId = _connectionId;
    if (_voiceCancelled || connId == null || connId.isEmpty) {
      await _voice.cancel();
      _voiceCancelled = false;
      return;
    }
    final result = await _voice.stop();
    if (result == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording too short — hold the mic to record'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    HapticFeedback.lightImpact();
    final pending = _PendingVoice(
      id: 'pending-${_pendingVoiceSeq++}',
      durationMs: result.duration.inMilliseconds,
      waveform: result.waveform,
    );
    if (mounted) setState(() => _pendingVoices.add(pending));
    try {
      final sent = await sendVoiceMessage(
        connectionId: connId,
        localPath: result.path,
        duration: result.duration,
        waveform: result.waveform,
        // Claim the message id on the placeholder *before* the Firestore
        // write lands. The list builder filters out promoted ids, so the
        // incoming snapshot doc never renders as a second bubble.
        onMessageId: (id) {
          if (!mounted) return;
          setState(() => pending.messageId = id);
        },
      );
      // Upload finished — fill in the URL so the placeholder swaps into
      // the real _VoicePlayer in-place.
      if (mounted) {
        setState(() {
          pending.messageId = sent.messageId;
          pending.url = sent.url;
        });
      }
    } catch (e, st) {
      debugPrint('sendVoiceMessage failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Voice send failed: $e')));
      if (mounted) setState(() => _pendingVoices.remove(pending));
    }
  }

  Future<void> _cancelRecording() async {
    _voiceCancelled = true;
    await _stopRecording();
  }

  void _showBuzzPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Buzz',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => _BuzzPopup(
        displayCount: _displayCount,
        connected: _connected,
        sentLabels: _sentLabels,
        partnerName: _partnerName,
        onTap: _onBuzzTap,
        onLabelComplete: _removeSentLabel,
      ),
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final connId = _connectionId;
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: c.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(c),
            Divider(height: 1, color: c.cardBorder),
            Expanded(
              child: connId == null || myUid == null
                  ? const SizedBox.shrink()
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Center(
                            child: CircularProgressIndicator(color: c.primary),
                          );
                        }
                        final docs = snapshot.data!.docs
                            .where(
                              (d) =>
                                  (d.data()['type'] as String?) == 'text' ||
                                  (d.data()['type'] as String?) == 'buzz' ||
                                  (d.data()['type'] as String?) == 'voice',
                            )
                            .toList();
                        // Hide docs that already have a pending placeholder
                        // standing in for them — the placeholder swaps into
                        // the real player in-place once upload completes.
                        final promotedIds = _pendingVoices
                            .where((p) => p.messageId != null)
                            .map((p) => p.messageId!)
                            .toSet();
                        if (promotedIds.isNotEmpty) {
                          docs.removeWhere((d) => promotedIds.contains(d.id));
                        }
                        if (docs.isEmpty && _pendingVoices.isEmpty) {
                          return Center(
                            child: Text(
                              'Say hi 👋',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                color: c.textDim,
                              ),
                            ),
                          );
                        }
                        // Merge docs and pending placeholders into a single
                        // list ordered oldest → newest by timestamp, so a
                        // text sent after a voice recording slots in below
                        // the placeholder instead of jumping above it.
                        final items = <_ChatItem>[
                          for (final d in docs)
                            _ChatItem.doc(
                              d,
                              (d.data()['timestamp'] is Timestamp)
                                  ? (d.data()['timestamp'] as Timestamp)
                                        .toDate()
                                  : DateTime.now(),
                            ),
                          for (final p in _pendingVoices)
                            _ChatItem.pending(p, p.createdAt),
                        ];
                        items.sort((a, b) => a.time.compareTo(b.time));
                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          // Keep all bubble state alive across new messages
                          // so voice players don't reload when text arrives.
                          addAutomaticKeepAlives: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            // reverse:true → i=0 is the newest at the bottom.
                            final idx = items.length - 1 - i;
                            final item = items[idx];
                            if (item.pending != null) {
                              final p = item.pending!;
                              // showTime when previous item is from a
                              // different sender (or there is none).
                              final prevFromUid = idx > 0
                                  ? (items[idx - 1].doc != null
                                        ? items[idx - 1].doc!.data()['fromUid']
                                              as String?
                                        : myUid)
                                  : null;
                              final showTime = prevFromUid != myUid;
                              return KeyedSubtree(
                                key: ValueKey(p.id),
                                child: _buildPendingVoiceBubble(
                                  c,
                                  p,
                                  time: _formatLocalTime(p.createdAt),
                                  showTime: showTime,
                                ),
                              );
                            }
                            final doc = item.doc!;
                            final data = doc.data();
                            final mine = data['fromUid'] == myUid;
                            final type = data['type'] as String? ?? 'text';
                            final ts = data['timestamp'];
                            String? prevFromUid;
                            if (idx > 0) {
                              final prev = items[idx - 1];
                              prevFromUid = prev.doc != null
                                  ? prev.doc!.data()['fromUid'] as String?
                                  : myUid; // pending voices are always mine
                            }
                            final showTime =
                                idx == 0 || prevFromUid != data['fromUid'];
                            return KeyedSubtree(
                              key: ValueKey(doc.id),
                              child: _buildBubble(
                                c,
                                messageId: doc.id,
                                mine: mine,
                                type: type,
                                text: (data['text'] ?? '') as String,
                                voiceUrl: data['url'] as String?,
                                voiceDurationMs: (data['duration'] as num?)
                                    ?.toInt(),
                                voiceWaveform: _waveformFor(doc.id, data),
                                time: _formatTimestamp(ts),
                                showTime: showTime,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            _buildInputBar(c),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts is! Timestamp) return '';
    return _formatLocalTime(ts.toDate());
  }

  String _formatLocalTime(DateTime dt) {
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour < 12 ? 'AM' : 'PM';
    return '$h12:$m $p';
  }

  List<double> _waveformFor(String docId, Map<String, dynamic> data) {
    final cached = _waveformCache[docId];
    if (cached != null) return cached;
    final raw = (data['waveform'] as List?) ?? const [];
    final parsed = raw
        .map((e) => (e as num).toDouble())
        .toList(growable: false);
    _waveformCache[docId] = parsed;
    return parsed;
  }

  Widget _buildHeader(NexaryoColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              color: c.textDim,
              size: 24,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.primary.withValues(alpha: 0.15),
              border: Border.all(color: c.primary, width: 2),
            ),
            child: Center(
              child: Text(
                (_partnerName?.isNotEmpty ?? false)
                    ? _partnerName![0].toUpperCase()
                    : '?',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _partnerName ?? '...',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    StreamBuilder<bool>(
                      stream: PresenceService.watchOnline(widget.partnerUid),
                      builder: (context, snap) {
                        final online = snap.data ?? false;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 8,
                              width: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: online
                                    ? const Color(0xFF4CAF50)
                                    : c.textDim,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              online ? 'Online' : 'Offline',
                              style: GoogleFonts.montserrat(
                                fontSize: 12,
                                color: c.textDim,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: c.primary,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                HapticFeedback.mediumImpact();
                _inputFocus.unfocus();
                _showBuzzPopup();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedNotification01,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Buzz',
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(
    NexaryoColors c, {
    required String messageId,
    required bool mine,
    required String type,
    required String text,
    required String time,
    required bool showTime,
    String? voiceUrl,
    int? voiceDurationMs,
    List<double> voiceWaveform = const [],
  }) {
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final cross = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final isBuzz = type == 'buzz';
    final isVoice = type == 'voice';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: align,
        child: Column(
          crossAxisAlignment: cross,
          children: [
            if (showTime && time.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                child: Text(
                  time,
                  style: GoogleFonts.montserrat(fontSize: 10, color: c.textDim),
                ),
              ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isVoice ? 8 : 14,
                vertical: isVoice ? 6 : 10,
              ),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              decoration: BoxDecoration(
                color: mine ? c.primary : c.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
                border: Border.all(
                  color: mine ? Colors.transparent : c.cardBorder,
                ),
              ),
              child: isBuzz
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedNotification01,
                          color: mine ? Colors.white : c.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Buzz!',
                          style: GoogleFonts.montserrat(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: mine ? Colors.white : c.textPrimary,
                          ),
                        ),
                      ],
                    )
                  : isVoice
                  ? (voiceUrl != null && voiceUrl.isNotEmpty
                        ? _VoicePlayer(
                            key: ValueKey('voice-$messageId'),
                            messageId: messageId,
                            url: voiceUrl,
                            durationMs: voiceDurationMs ?? 0,
                            waveform: voiceWaveform,
                            mine: mine,
                            colors: c,
                          )
                        : Text(
                            'Voice message unavailable',
                            style: GoogleFonts.montserrat(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: mine ? Colors.white70 : c.textDim,
                            ),
                          ))
                  : Text(
                      text,
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: mine ? Colors.white : c.textPrimary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingVoiceBubble(
    NexaryoColors c,
    _PendingVoice p, {
    String time = '',
    bool showTime = false,
  }) {
    // Mirrors the "mine" voice bubble's shell exactly so the layout doesn't
    // shift when the placeholder is swapped for the real player.
    const fg = Colors.white;
    const track = Colors.white24;
    final total = Duration(milliseconds: p.durationMs);
    String fmt(Duration d) {
      final m = d.inMinutes.toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    final ready = p.messageId != null && p.url != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showTime && time.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                child: Text(
                  time,
                  style: GoogleFonts.montserrat(fontSize: 10, color: c.textDim),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: ready
                  ? _VoicePlayer(
                      key: ValueKey('voice-${p.messageId}'),
                      messageId: p.messageId!,
                      url: p.url!,
                      durationMs: p.durationMs,
                      waveform: p.waveform,
                      mine: true,
                      colors: c,
                    )
                  : SizedBox(
                      width: 220,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 28,
                              child: CustomPaint(
                                painter: _WaveformPainter(
                                  samples: p.waveform,
                                  progress: 0,
                                  playedColor: fg,
                                  unplayedColor: track,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            fmt(total),
                            style: GoogleFonts.montserrat(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(NexaryoColors c) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isRecording,
      builder: (context, recording, _) {
        if (recording) return _buildRecordingBar(c);
        return _buildNormalInputBar(c);
      },
    );
  }

  Widget _buildRecordingBar(NexaryoColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.primary),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFFE53935),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<Duration>(
              valueListenable: _recordElapsed,
              builder: (_, elapsed, __) {
                final remaining = VoiceRecorderService.maxDuration - elapsed;
                final secs = remaining.inSeconds.clamp(0, 99);
                return Text(
                  '${elapsed.inSeconds.toString().padLeft(2, '0')}s  ·  ${secs}s left',
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                );
              },
            ),
            const Spacer(),
            TextButton(
              onPressed: _cancelRecording,
              child: Text(
                'Cancel',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textDim,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedSent,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: _stopRecording,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalInputBar(NexaryoColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.cardBorder),
            ),
            child: IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedImage01,
                color: c.textSecondary,
                size: 20,
              ),
              onPressed: () {},
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _inputFocus,
              style: GoogleFonts.montserrat(fontSize: 14, color: c.textPrimary),
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: c.textDim,
                ),
                filled: true,
                fillColor: c.card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: c.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: c.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: _hasText,
            builder: (context, hasText, _) {
              if (hasText) {
                return Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: IconButton(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedSent,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: _send,
                  ),
                );
              }
              return GestureDetector(
                onTap: () {
                  if (_isRecording.value) {
                    // Tap-started session: tap again to send.
                    _stopRecording();
                  } else {
                    _startRecording();
                  }
                },
                onLongPressStart: (_) {
                  if (!_isRecording.value) _startRecording();
                },
                onLongPressEnd: (_) {
                  if (_isRecording.value) _stopRecording();
                },
                child: Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedMic01,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChatItem {
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  final _PendingVoice? pending;
  final DateTime time;
  _ChatItem._(this.doc, this.pending, this.time);
  factory _ChatItem.doc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    DateTime t,
  ) => _ChatItem._(d, null, t);
  factory _ChatItem.pending(_PendingVoice p, DateTime t) =>
      _ChatItem._(null, p, t);
}

class _PendingVoice {
  final String id;
  final int durationMs;
  final List<double> waveform;
  final DateTime createdAt;
  String? messageId;
  String? url;
  _PendingVoice({
    required this.id,
    required this.durationMs,
    required this.waveform,
  }) : createdAt = DateTime.now();
}

class _VoicePlayer extends StatefulWidget {
  final String messageId;
  final String url;
  final int durationMs;
  final List<double> waveform;
  final bool mine;
  final NexaryoColors colors;

  const _VoicePlayer({
    super.key,
    required this.messageId,
    required this.url,
    required this.durationMs,
    required this.mine,
    required this.colors,
    this.waveform = const [],
  });

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  late final AudioPlayer _player;
  bool _ready = false;
  String? _loadError;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _player = VoicePlayerRegistry.instance.playerFor(widget.messageId);
    _stateSub = _player.playerStateStream.listen((s) {
      if (s.playing) {
        VoicePlayerRegistry.instance.markActive(widget.messageId);
      }
    });
    _init();
  }

  Future<void> _init() async {
    // If the registry already loaded this player, just mark ready.
    if (_player.audioSource != null && _player.duration != null) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    try {
      await VoicePlayerRegistry.instance.ensureLoaded(
        messageId: widget.messageId,
        url: widget.url,
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  @override
  void dispose() {
    // Note: do NOT dispose the player \u2014 it lives in the registry so it
    // survives widget rebuilds caused by new messages arriving.
    _stateSub?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final fg = widget.mine ? Colors.white : c.primary;
    final track = widget.mine ? Colors.white24 : c.cardBorder;
    final total = Duration(milliseconds: widget.durationMs);
    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (_, snap) {
              final playing = snap.data?.playing ?? false;
              final completed =
                  snap.data?.processingState == ProcessingState.completed;
              if (_loadError != null) {
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(Icons.error_outline, color: fg),
                  onPressed: () {
                    setState(() => _loadError = null);
                    _init();
                  },
                );
              }
              if (!_ready) {
                return SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(fg),
                      ),
                    ),
                  ),
                );
              }
              return IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  playing && !completed ? Icons.pause : Icons.play_arrow,
                  color: fg,
                ),
                onPressed: () async {
                  if (completed) {
                    await _player.seek(Duration.zero);
                    await _player.play();
                  } else if (playing) {
                    await _player.pause();
                  } else {
                    await _player.play();
                  }
                },
              );
            },
          ),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (_, snap) {
                final pos = snap.data ?? Duration.zero;
                final progress = total.inMilliseconds == 0
                    ? 0.0
                    : (pos.inMilliseconds / total.inMilliseconds).clamp(
                        0.0,
                        1.0,
                      );
                return Builder(
                  builder: (innerCtx) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) async {
                      if (!_ready || total.inMilliseconds == 0) return;
                      final box = innerCtx.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final ratio = (d.localPosition.dx / box.size.width).clamp(
                        0.0,
                        1.0,
                      );
                      await _player.seek(
                        Duration(
                          milliseconds: (total.inMilliseconds * ratio).round(),
                        ),
                      );
                    },
                    child: SizedBox(
                      height: 28,
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          samples: widget.waveform,
                          progress: progress,
                          playedColor: fg,
                          unplayedColor: track,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmt(total),
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final data = samples.isEmpty ? List<double>.filled(40, 0.15) : samples;
    const barWidth = 2.0;
    const gap = 2.0;
    final available = size.width;
    final maxBars = ((available + gap) / (barWidth + gap)).floor();
    final barCount = data.length < maxBars ? data.length : maxBars;
    if (barCount == 0) return;
    final totalWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = (available - totalWidth) / 2;
    final centerY = size.height / 2;
    final playedBars = (progress * barCount).round();

    final paintPlayed = Paint()
      ..color = playedColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;
    final paintUnplayed = Paint()
      ..color = unplayedColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < barCount; i++) {
      // Re-sample evenly across the source array.
      final srcIdx = (i * data.length / barCount).floor();
      final amp = data[srcIdx].clamp(0.0, 1.0);
      final h = (size.height * amp).clamp(2.0, size.height);
      final x = startX + i * (barWidth + gap) + barWidth / 2;
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        i < playedBars ? paintPlayed : paintUnplayed,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) {
    // Samples are immutable per message; only progress / colors change
    // during playback. Skip a deep list compare.
    return old.progress != progress ||
        old.samples.length != samples.length ||
        old.playedColor != playedColor ||
        old.unplayedColor != unplayedColor;
  }
}

class _BuzzPopup extends StatelessWidget {
  final ValueListenable<int> displayCount;
  final ValueListenable<bool> connected;
  final ValueListenable<List<int>> sentLabels;
  final String? partnerName;
  final VoidCallback onTap;
  final ValueChanged<int> onLabelComplete;

  const _BuzzPopup({
    required this.displayCount,
    required this.connected,
    required this.sentLabels,
    required this.partnerName,
    required this.onTap,
    required this.onLabelComplete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: c.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: double.infinity,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedCancel01,
                    color: c.textSecondary,
                    size: 22,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: connected,
                      builder: (_, isConnected, __) {
                        return Text(
                          isConnected
                              ? 'Buzzing ${partnerName ?? "partner"}'
                              : 'Not connected yet',
                          style: GoogleFonts.montserrat(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isConnected ? c.primary : c.textDim,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder<bool>(
                      valueListenable: connected,
                      builder: (_, isConnected, __) {
                        return Material(
                          color: isConnected
                              ? c.primary
                              : c.primary.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(100),
                          child: InkWell(
                            onTap: isConnected ? onTap : null,
                            borderRadius: BorderRadius.circular(100),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 48,
                                vertical: 16,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ValueListenableBuilder<int>(
                                    valueListenable: displayCount,
                                    builder: (_, count, __) {
                                      return Text(
                                        count == 0 ? 'Tap' : '$count',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      );
                                    },
                                  ),
                                  Text(
                                    'Buzz Bee',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<List<int>>(
                valueListenable: sentLabels,
                builder: (_, labels, __) {
                  return Stack(
                    children: [
                      for (final k in labels)
                        _SentFloat(
                          key: ValueKey(k),
                          color: c.primary,
                          onComplete: () => onLabelComplete(k),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SentFloat extends StatefulWidget {
  final Color color;
  final VoidCallback onComplete;
  const _SentFloat({super.key, required this.color, required this.onComplete});

  @override
  State<_SentFloat> createState() => _SentFloatState();
}

class _SentFloatState extends State<_SentFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _offset;
  late final double _xShift;

  @override
  void initState() {
    super.initState();
    _xShift = (Random().nextDouble() - 0.5) * 60;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _offset = Tween<double>(
      begin: 0,
      end: -100,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Positioned(
          top: 110 + _offset.value,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: _opacity.value,
              child: Transform.translate(
                offset: Offset(_xShift, 0),
                child: Center(
                  child: Text(
                    'sent',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
