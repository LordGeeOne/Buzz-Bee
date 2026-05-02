import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/connection_service.dart';
import '../services/call_service.dart';
import '../services/image_message_service.dart';
import '../services/message_actions_service.dart';
import '../services/presence_service.dart';
import '../services/user_cache.dart';
import '../services/voice_player_registry.dart';
import '../services/voice_recorder_service.dart';
import '../theme/nexaryo_colors.dart';
import '../utils/time_formatter.dart';
import '../widgets/call_banner_overlay.dart';
import '../widgets/chat_background.dart';
import '../widgets/message_actions_sheet.dart';
import 'call_screen.dart';
import 'profile_screen.dart';

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
  // Idle window: resets on every tap. Fires when the user pauses, so a
  // burst of taps coalesces into a single Firestore transaction.
  static const Duration _flushIdleWindow = Duration(seconds: 5);
  // Max-age cap: started on the FIRST tap of a batch and NOT reset on
  // subsequent taps. Guarantees the partner sees a buzz at least every
  // _flushMaxWindow even during a sustained tap-storm — otherwise the
  // idle timer alone would let a frantic user hold the entire batch in
  // local state for an unbounded amount of time.
  static const Duration _flushMaxWindow = Duration(seconds: 5);

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();

  String? _connectionId;
  String? _partnerName;
  String? _partnerPhoto;

  /// First whitespace-separated token of [name], or [fallback] when name is
  /// null/empty. Used by the chat header so we show "Alex" instead of
  /// "Alex Johnson Smith" while the rest of the app keeps the full name.
  static String _firstNameOrFallback(String? name, String fallback) {
    if (name == null) return fallback;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return fallback;
    final space = trimmed.indexOf(RegExp(r'\s'));
    return space == -1 ? trimmed : trimmed.substring(0, space);
  }

  /// Human-readable "Last seen ..." label for a partner that's currently
  /// offline. Falls back to "Offline" when no heartbeat has ever been
  /// recorded.
  static String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'Offline';
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.inSeconds < 60) return 'Last seen just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return 'Last seen $m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inHours < 24 && now.day == lastSeen.day) {
      final h = lastSeen.hour;
      final m = lastSeen.minute.toString().padLeft(2, '0');
      final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final ampm = h >= 12 ? 'PM' : 'AM';
      return 'Last seen today at $hour12:$m $ampm';
    }
    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    final lsDate = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);
    if (lsDate == yesterday) {
      final h = lastSeen.hour;
      final m = lastSeen.minute.toString().padLeft(2, '0');
      final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final ampm = h >= 12 ? 'PM' : 'AM';
      return 'Last seen yesterday at $hour12:$m $ampm';
    }
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return 'Last seen ${days[lastSeen.weekday - 1]}';
    }
    final d = lastSeen.day.toString().padLeft(2, '0');
    final mo = lastSeen.month.toString().padLeft(2, '0');
    return 'Last seen $d/$mo/${lastSeen.year}';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _messagesStream;
  int _serverSent = 0;
  int _pendingCount = 0;
  Timer? _flushTimer;
  Timer? _flushMaxTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _connSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingSub;
  DateTime? _incomingSubscribedAt;

  // Live values consumed by the popup so it rebuilds in-place on tap/sync.
  final ValueNotifier<int> _displayCount = ValueNotifier<int>(0);
  // null = not yet known (don't show disconnected UI), true = connected,
  // false = confirmed disconnected (show disabled composer).
  final ValueNotifier<bool?> _connected = ValueNotifier<bool?>(null);
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

  // Image messages currently uploading. Same lifecycle as _pendingVoices:
  // local placeholder bubble that swaps in once Storage upload completes.
  final List<_PendingImage> _pendingImages = [];
  int _pendingImageSeq = 0;

  // When non-null, the composer's send button commits an edit instead of
  // sending a new message. Tied to a specific message doc id.
  String? _editingMessageId;

  // When non-null, the next outgoing message attaches a `replyTo` chip
  // pointing at this original message. Mutually exclusive with edit mode
  // (entering one clears the other).
  _ReplyDraft? _replyDraft;

  // Cache of parsed waveform arrays per messageId so we don't re-allocate
  // a `List<double>` on every Firestore snapshot.
  final Map<String, List<double>> _waveformCache = {};

  // Per-message idempotency for ephemeral-media TTL marking. Once we've
  // written `deliveredAt` (or `seenAt + expireAt`) for a doc this session,
  // we never write it again — Firestore would reject anyway, but skipping
  // the round-trip is cheaper.
  final Set<String> _deliveredMarked = {};
  final Set<String> _seenMarked = {};

  // True while the chat screen is on top AND the app is foreground. Drives
  // whether incoming partner voice messages get stamped with `seenAt`
  // (which starts the 1-hour TTL countdown).
  bool _chatForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputFocus.addListener(_onFocusChange);
    _textController.addListener(_onTextChanged);
    // Seed partner name/photo synchronously from the process cache so the
    // header doesn't visibly load when entering the chat from the dashboard.
    final cached = UserCache.get(widget.partnerUid);
    if (cached != null) {
      _partnerName = cached['name'] as String?;
      _partnerPhoto = cached['photoURL'] as String?;
    }
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

    // Routes through UserCache: skips Firestore entirely if already cached.
    final pData = await UserCache.fetch(widget.partnerUid);
    if (!mounted) return;
    setState(() {
      _partnerName = pData?['name'] as String? ?? _partnerName;
      _partnerPhoto = pData?['photoURL'] as String? ?? _partnerPhoto;
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
    _flushMaxTimer?.cancel();
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
      _chatForeground = true;
      if (connId != null && connId.isNotEmpty) {
        unawaited(ConnectionService.setViewing(connId, true));
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _chatForeground = false;
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

      // Ephemeral-media TTL marking — fire BEFORE the haptic timestamp
      // gate so we still mark old undelivered docs from prior sessions.
      // Voice / image only; skipped while still uploading.
      if ((type == 'voice' || type == 'image') && data['uploading'] != true) {
        _markEphemeral(change.doc.reference, change.doc.id, data);
      }

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

  /// Stamp `deliveredAt` once any partner ephemeral message lands. If the
  /// chat is currently foreground, also stamp `seenAt + expireAt = now+1h`,
  /// which arms Firestore's TTL policy on `expireAt` to delete the doc
  /// (and via the `onMessageDeleted` Cloud Function, the Storage object).
  void _markEphemeral(
    DocumentReference<Map<String, dynamic>> ref,
    String id,
    Map<String, dynamic> data,
  ) {
    final hasDelivered = data['deliveredAt'] != null;
    final hasSeen = data['seenAt'] != null;
    final updates = <String, dynamic>{};
    if (!hasDelivered && _deliveredMarked.add(id)) {
      updates['deliveredAt'] = FieldValue.serverTimestamp();
    }
    if (_chatForeground && !hasSeen && _seenMarked.add(id)) {
      updates['seenAt'] = FieldValue.serverTimestamp();
      updates['expireAt'] = Timestamp.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch + 3600 * 1000,
      );
    }
    if (updates.isEmpty) return;
    unawaited(ref.update(updates).catchError((_) {}));
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
    if (!snap.exists) {
      // The other user (or we) disconnected. Block sending.
      _connected.value = false;
      return;
    }
    _connected.value = true;
    final data = snap.data();
    if (data == null) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final sentMap = (data['sent'] as Map?) ?? const {};
    final newServerSent = ((sentMap[myUid] as num?) ?? 0).toInt();
    if (newServerSent < _serverSent) {
      _pendingCount = 0;
      _flushTimer?.cancel();
      _flushTimer = null;
      _flushMaxTimer?.cancel();
      _flushMaxTimer = null;
    }
    _serverSent = newServerSent;
    // Display count reflects ONLY the current unsent batch — it resets
    // to 0 after each successful flush so the popup feels like a fresh
    // counter for the next burst rather than a session-cumulative tally.
    _displayCount.value = _pendingCount;
  }

  void _onBuzzTap() {
    HapticFeedback.vibrate();
    _pendingCount++;
    _displayCount.value = _pendingCount;
    _sentLabels.value = [..._sentLabels.value, _sentKey++];
    // Idle timer always resets — enables coalescing of bursts.
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushIdleWindow, _flushPending);
    // Max-age cap is only armed on the first tap of a batch; sustained
    // tapping then triggers a flush at most _flushMaxWindow after the
    // batch began, bounding partner-side latency.
    _flushMaxTimer ??= Timer(_flushMaxWindow, _flushPending);
  }

  void _removeSentLabel(int key) {
    _sentLabels.value = _sentLabels.value.where((k) => k != key).toList();
  }

  Future<void> _flushPending() async {
    final count = _pendingCount;
    final connId = _connectionId;
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushMaxTimer?.cancel();
    _flushMaxTimer = null;
    if (count <= 0 || connId == null || connId.isEmpty) return;
    _pendingCount = 0;
    // Reset the on-screen counter immediately so the user sees the
    // batch "leave" the moment we attempt the write. If the write
    // fails below we restore both the count and the display.
    if (mounted) _displayCount.value = 0;
    try {
      await ConnectionService.sendBuzz(connectionId: connId, count: count);
    } catch (_) {
      // Network/transaction failure — put the buzzes back so the next
      // flush retries them. (Routine offline writes are queued by the
      // Firestore SDK; this branch handles the rarer hard failures like
      // exhausted transaction retries or auth loss.)
      if (!mounted) return;
      _pendingCount += count;
      _displayCount.value = _pendingCount;
      _flushTimer = Timer(_flushIdleWindow, _flushPending);
      _flushMaxTimer ??= Timer(_flushMaxWindow, _flushPending);
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
    final editId = _editingMessageId;
    final reply = _replyDraft;
    _textController.clear();
    if (editId != null) {
      // Commit the edit and exit edit mode. Firestore rules enforce the
      // 1h window server-side; we just call the helper.
      setState(() => _editingMessageId = null);
      try {
        await MessageActionsService.editText(
          connectionId: connId,
          messageId: editId,
          newText: text,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Edit failed: $e')));
      }
      return;
    }
    if (reply != null) setState(() => _replyDraft = null);
    await ConnectionService.sendMessage(
      connectionId: connId,
      type: 'text',
      text: text,
      replyTo: reply?.payload,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Cancel an in-progress edit. Clears the composer and the banner.
  void _cancelEdit() {
    if (_editingMessageId == null) return;
    _textController.clear();
    _hasText.value = false;
    setState(() => _editingMessageId = null);
  }

  /// Cancel a pending reply. The composer text is preserved (the user
  /// may still want to send their typed message without quoting).
  void _cancelReply() {
    if (_replyDraft == null) return;
    setState(() => _replyDraft = null);
  }

  /// Begin replying to [data] (any non-deleted message). Builds the small
  /// denormalized payload now so the chip can render even if the original
  /// later changes (edited / reacted / TTL'd).
  void _startReply(String messageId, Map<String, dynamic> data) {
    final payload = buildReplyTo(messageId: messageId, data: data);
    if (payload == null) return;
    setState(() {
      _editingMessageId = null;
      _replyDraft = _ReplyDraft(
        messageId: messageId,
        fromUid: (data['fromUid'] as String?) ?? '',
        type: (data['type'] as String?) ?? 'text',
        preview: payload['preview'] as String?,
        payload: payload,
      );
    });
    _inputFocus.requestFocus();
  }

  /// Begin editing [data] (a text message). Populates the composer with
  /// the existing text and shows a small banner above the input bar.
  void _startEdit(String messageId, Map<String, dynamic> data) {
    final text = (data['text'] as String?) ?? '';
    _textController
      ..text = text
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
    _hasText.value = text.isNotEmpty;
    setState(() {
      _replyDraft = null;
      _editingMessageId = messageId;
    });
    _inputFocus.requestFocus();
  }

  /// Pick up to [kImagesPerMessage] images, register a placeholder bubble
  /// and kick off the compress + upload pipeline. The bubble swaps for the
  /// real Firestore doc as soon as the upload completes.
  Future<void> _pickAndSendImages() async {
    final connId = _connectionId;
    if (connId == null || connId.isEmpty) return;
    if (_connected.value == false) return;
    HapticFeedback.selectionClick();
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage(limit: kImagesPerMessage);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open gallery: $e')));
      return;
    }
    if (picked.isEmpty) return;
    final capped = picked.take(kImagesPerMessage).toList();
    final reply = _replyDraft;
    if (reply != null) setState(() => _replyDraft = null);
    final pending = _PendingImage(
      id: 'pending-img-${_pendingImageSeq++}',
      previews: capped,
    );
    if (mounted) setState(() => _pendingImages.add(pending));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      await sendImageMessage(
        connectionId: connId,
        picked: capped,
        replyTo: reply?.payload,
        onMessageId: (id) {
          if (!mounted) return;
          setState(() => pending.messageId = id);
        },
      );
      if (mounted) setState(() => _pendingImages.remove(pending));
    } catch (e, st) {
      debugPrint('sendImageMessage failed: $e\n$st');
      if (!mounted) return;
      // Best-effort: tear down the placeholder doc the service wrote in
      // phase 1 so the recipient never sees a stuck "uploading" message.
      final mid = pending.messageId;
      if (mid != null) {
        try {
          await FirebaseFirestore.instance
              .collection('connections')
              .doc(connId)
              .collection('messages')
              .doc(mid)
              .delete();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _pendingImages.remove(pending));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image send failed: $e')));
    }
  }

  bool _voiceCallStarting = false;

  Future<void> _startVoiceCall() async {
    final connId = _connectionId;
    if (connId == null || connId.isEmpty) return;
    if (CallService.instance.inCall) return;
    if (_voiceCallStarting) return;
    _voiceCallStarting = true;
    HapticFeedback.mediumImpact();
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
        return;
      }
      final callId = await CallService.instance.startCall(
        connectionId: connId,
        calleeUid: widget.partnerUid,
        calleeName: _partnerName,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            callId: callId,
            connectionId: connId,
            peerUid: widget.partnerUid,
            peerName: _partnerName ?? '',
            isIncoming: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start call: $e')));
    } finally {
      _voiceCallStarting = false;
    }
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
              child: ChatBackground(
                color: c.primary,
                child: connId == null || myUid == null
                    ? const SizedBox.shrink()
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _messagesStream,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: c.primary,
                              ),
                            );
                          }
                          final docs = snapshot.data!.docs.where((d) {
                            final data = d.data();
                            final type = data['type'] as String?;
                            if (type != 'text' &&
                                type != 'buzz' &&
                                type != 'voice' &&
                                type != 'image' &&
                                type != 'call') {
                              return false;
                            }
                            // Hide voice / image messages still uploading
                            // (phase-1 write before Storage upload completes).
                            // The sender shows a local pending placeholder;
                            // the recipient simply waits for phase-2 to land.
                            if ((type == 'voice' || type == 'image') &&
                                data['uploading'] == true) {
                              return false;
                            }
                            return true;
                          }).toList();
                          // Hide docs that already have a pending placeholder
                          // standing in for them — the placeholder swaps into
                          // the real player in-place once upload completes.
                          final promotedIds = <String>{
                            ..._pendingVoices
                                .where((p) => p.messageId != null)
                                .map((p) => p.messageId!),
                            ..._pendingImages
                                .where((p) => p.messageId != null)
                                .map((p) => p.messageId!),
                          };
                          if (promotedIds.isNotEmpty) {
                            docs.removeWhere((d) => promotedIds.contains(d.id));
                          }
                          if (docs.isEmpty &&
                              _pendingVoices.isEmpty &&
                              _pendingImages.isEmpty) {
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
                            for (final p in _pendingImages)
                              _ChatItem.pendingImage(p, p.createdAt),
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
                                          ? items[idx - 1].doc!
                                                    .data()['fromUid']
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
                              if (item.pendingImage != null) {
                                final p = item.pendingImage!;
                                final prevFromUid = idx > 0
                                    ? (items[idx - 1].doc != null
                                          ? items[idx - 1].doc!
                                                    .data()['fromUid']
                                                as String?
                                          : myUid)
                                    : null;
                                final showTime = prevFromUid != myUid;
                                return KeyedSubtree(
                                  key: ValueKey(p.id),
                                  child: _buildPendingImageBubble(
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
                              // While the server timestamp is still pending
                              // (`hasPendingWrites`), `ts` is null. Fall back
                              // to the merged item's local time so freshly
                              // sent messages always show a timestamp.
                              final tsLabel = (ts is Timestamp)
                                  ? _formatTimestamp(ts)
                                  : _formatLocalTime(item.time);
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
                                child: type == 'call'
                                    ? _buildCallLogBubble(
                                        c,
                                        mine: mine,
                                        outcome:
                                            (data['callOutcome'] as String?) ??
                                            'missed',
                                        durationMs:
                                            ((data['durationMs'] as num?) ?? 0)
                                                .toInt(),
                                        time: tsLabel,
                                        showTime: showTime,
                                      )
                                    : _buildBubble(
                                        c,
                                        messageId: doc.id,
                                        data: data,
                                        mine: mine,
                                        type: type,
                                        text: (data['text'] ?? '') as String,
                                        voiceUrl: data['url'] as String?,
                                        voiceDurationMs:
                                            (data['duration'] as num?)?.toInt(),
                                        voiceWaveform: _waveformFor(
                                          doc.id,
                                          data,
                                        ),
                                        time: tsLabel,
                                        showTime: showTime,
                                      ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
            _buildEditBanner(c),
            _buildReplyBanner(c),
            _buildInputBar(c),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts is! Timestamp) return '';
    return TimeFormatter.formatLocalTime(ts.toDate());
  }

  String _formatLocalTime(DateTime dt) => TimeFormatter.formatLocalTime(dt);

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
    return Material(
      color: c.surface,
      child: Padding(
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
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(uid: widget.partnerUid),
                  ),
                );
              },
              child: Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.primary.withValues(alpha: 0.15),
                  image: (_partnerPhoto != null && _partnerPhoto!.isNotEmpty)
                      ? DecorationImage(
                          image: UserCache.avatarFor(_partnerPhoto!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (_partnerPhoto != null && _partnerPhoto!.isNotEmpty)
                    ? null
                    : Center(
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
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _firstNameOrFallback(_partnerName, '...'),
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: StreamBuilder<PresenceSnapshot>(
                          stream: PresenceService.watchPresence(
                            widget.partnerUid,
                          ),
                          builder: (context, snap) {
                            final presence =
                                snap.data ??
                                const PresenceSnapshot(online: false);
                            final online = presence.online;
                            final label = online
                                ? 'Online'
                                : _formatLastSeen(presence.lastSeen);
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
                                Flexible(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.montserrat(
                                      fontSize: 10,
                                      color: c.textDim,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Voice call',
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedCall02,
                color: c.primary,
                size: 24,
              ),
              onPressed: _startVoiceCall,
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
      ),
    );
  }

  Widget _buildBubble(
    NexaryoColors c, {
    required String messageId,
    required Map<String, dynamic> data,
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
    final isImage = type == 'image';
    final isDeleted = data['deletedAt'] != null;
    final isEdited = data['editedAt'] != null;
    final reactions = (data['reactions'] as Map?)?.cast<String, dynamic>();

    Widget bubbleBody;
    if (isDeleted) {
      bubbleBody = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedDelete02,
            color: mine ? Colors.white70 : c.textDim,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            mine ? 'You deleted this message' : 'This message was deleted',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: mine ? Colors.white70 : c.textDim,
            ),
          ),
        ],
      );
    } else if (isBuzz) {
      // The buzz doc encodes how many taps were coalesced into this
      // batch via `count` (defaults to 1 for legacy docs without it).
      final buzzCount = ((data['count'] as num?) ?? 1).toInt();
      bubbleBody = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedNotification01,
            color: mine ? Colors.white : c.primary,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            buzzCount > 1 ? 'Buzz! ×$buzzCount' : 'Buzz!',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: mine ? Colors.white : c.textPrimary,
            ),
          ),
        ],
      );
    } else if (isVoice) {
      bubbleBody = (voiceUrl != null && voiceUrl.isNotEmpty)
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
            );
    } else if (isImage) {
      final images = ((data['images'] as List?) ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      bubbleBody = _ImageGrid(
        images: images,
        onTap: (i) => _openImageViewer(images, i),
      );
    } else {
      bubbleBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LinkifiedText(
            text: text,
            style: GoogleFonts.montserrat(
              fontSize: 14,
              color: mine ? Colors.white : c.textPrimary,
            ),
            linkColor: mine ? Colors.white : c.primary,
          ),
          if (isEdited)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'edited',
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: mine ? Colors.white70 : c.textDim,
                ),
              ),
            ),
        ],
      );
    }

    // Image messages get tighter padding so the photos meet the bubble
    // edge cleanly. Tombstones get the text padding for readability.
    final hPad = (isVoice || (isImage && !isDeleted)) ? 4.0 : 14.0;
    final vPad = (isVoice || (isImage && !isDeleted)) ? 4.0 : 10.0;

    // If this message is a reply, render a small quoted chip above the
    // body. Hidden on tombstones (the original is intentionally gone too,
    // visually).
    final replyTo = (!isDeleted)
        ? (data['replyTo'] as Map?)?.cast<String, dynamic>()
        : null;
    if (replyTo != null) {
      final chip = _ReplyChip(
        c: c,
        mine: mine,
        replyTo: replyTo,
        myUid: FirebaseAuth.instance.currentUser?.uid,
        partnerName: _partnerName,
      );
      bubbleBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bleed the chip slightly into the tighter image/voice padding
          // so it lines up with the bubble edges.
          Padding(
            padding: EdgeInsets.only(
              left: hPad < 14 ? (14 - hPad) : 0,
              right: hPad < 14 ? (14 - hPad) : 0,
              top: vPad < 10 ? (10 - vPad) : 0,
              bottom: 6,
            ),
            child: chip,
          ),
          bubbleBody,
        ],
      );
    }

    final bubble = Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      decoration: BoxDecoration(
        color: isDeleted
            ? (mine ? c.primary.withValues(alpha: 0.55) : c.card)
            : (mine ? c.primary : c.card),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
        border: Border.all(color: mine ? Colors.transparent : c.cardBorder),
      ),
      child: bubbleBody,
    );

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
            _SwipeToReply(
              enabled: data['deletedAt'] == null && type != 'buzz',
              onReply: () => _startReply(messageId, data),
              accent: c.primary,
              child: Builder(
                builder: (bubbleCtx) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: isBuzz && !isDeleted ? _showBuzzPopup : null,
                  onLongPress: isDeleted
                      ? null
                      : () => _onBubbleLongPress(
                          bubbleCtx,
                          messageId,
                          data,
                          mine,
                          type,
                          text,
                        ),
                  child: bubble,
                ),
              ),
            ),
            if (reactions != null && reactions.isNotEmpty && !isDeleted)
              Padding(
                padding: EdgeInsets.only(
                  top: 2,
                  left: mine ? 0 : 8,
                  right: mine ? 8 : 0,
                ),
                child: Builder(
                  builder: (badgeCtx) => _ReactionBadges(
                    c: c,
                    mine: mine,
                    reactions: reactions,
                    onTap: () => _onBubbleLongPress(
                      badgeCtx,
                      messageId,
                      data,
                      mine,
                      type,
                      text,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallLogBubble(
    NexaryoColors c, {
    required bool mine,
    required String outcome,
    required int durationMs,
    required String time,
    required bool showTime,
  }) {
    final isMissedish =
        outcome == 'missed' || outcome == 'declined' || outcome == 'failed';
    final iconColor = isMissedish ? const Color(0xFFE53935) : c.primary;
    final iconData = mine
        ? HugeIcons.strokeRoundedCallOutgoing01
        : HugeIcons.strokeRoundedCallIncoming01;

    String label;
    switch (outcome) {
      case 'completed':
        label = mine ? 'Outgoing call' : 'Incoming call';
        break;
      case 'missed':
        label = mine ? 'No answer' : 'Missed call';
        break;
      case 'declined':
        label = mine ? 'Declined' : 'You declined';
        break;
      case 'failed':
        label = "Couldn't connect";
        break;
      default:
        label = 'Call';
    }

    String fmtDuration(int ms) {
      if (ms <= 0) return '';
      final d = Duration(milliseconds: ms);
      final mins = d.inMinutes;
      final secs = d.inSeconds % 60;
      if (mins > 0) return '$mins min ${secs.toString().padLeft(2, '0')} sec';
      return '$secs sec';
    }

    final durationStr = fmtDuration(durationMs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () async {
              HapticFeedback.selectionClick();
              // If a call is already active, jump to it instead.
              final active = CallService.instance.current;
              if (active != null) {
                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      callId: active.callId,
                      connectionId: active.connectionId,
                      peerUid: active.peerUid,
                      peerName: active.peerName ?? _partnerName ?? '',
                      isIncoming: !active.isCaller,
                    ),
                  ),
                );
                return;
              }
              final ok = await showCallConfirmDialog(
                context,
                peerName: _partnerName ?? '',
              );
              if (ok && mounted) {
                _startVoiceCall();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(icon: iconData, color: iconColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  if (durationStr.isNotEmpty) ...[
                    Text(
                      ' · ',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: c.textDim,
                      ),
                    ),
                    Text(
                      durationStr,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: c.textDim,
                      ),
                    ),
                  ],
                  if (showTime && time.isNotEmpty) ...[
                    Text(
                      ' · ',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: c.textDim,
                      ),
                    ),
                    Text(
                      time,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: c.textDim,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    color: c.textDim,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
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

  /// Image-message placeholder. Renders the picked files via [Image.file]
  /// in the same grid layout as the eventual server bubble, so the swap
  /// is visually seamless when the upload finishes.
  Widget _buildPendingImageBubble(
    NexaryoColors c,
    _PendingImage p, {
    String time = '',
    bool showTime = false,
  }) {
    final tiles = p.previews
        .map<Map<String, dynamic>>((x) => {'localPath': x.path})
        .toList(growable: false);
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
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
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
                  child: _ImageGrid(images: tiles, onTap: null),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Edit-mode banner shown above the composer. Tapping the X cancels.
  Widget _buildEditBanner(NexaryoColors c) {
    if (_editingMessageId == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      color: c.card,
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedEdit02,
            color: c.primary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editing message',
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cancel edit',
            onPressed: _cancelEdit,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              color: c.textSecondary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  /// Reply-mode banner shown above the composer. The next message sent
  /// will attach the [_replyDraft] payload as its `replyTo` field.
  Widget _buildReplyBanner(NexaryoColors c) {
    final draft = _replyDraft;
    if (draft == null) return const SizedBox.shrink();
    final mine = draft.fromUid == FirebaseAuth.instance.currentUser?.uid;
    final author = mine ? 'yourself' : (_partnerName ?? 'them');
    final preview = draft.preview ?? _replyTypeLabel(draft.type);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      color: c.card,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: c.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $author',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            onPressed: _cancelReply,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              color: c.textSecondary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  /// Fallback label when a non-text message is being replied to (we
  /// don't denormalize the original payload into the chip).
  static String _replyTypeLabel(String type) {
    switch (type) {
      case 'image':
        return '📷 Photo';
      case 'voice':
        return '🎤 Voice message';
      case 'call':
        return '📞 Call';
      default:
        return 'Message';
    }
  }

  /// Open the long-press action sheet for [messageId]. Filters available
  /// actions based on age + message type, then dispatches the chosen one.
  Future<void> _onBubbleLongPress(
    BuildContext bubbleCtx,
    String messageId,
    Map<String, dynamic> data,
    bool mine,
    String type,
    String text,
  ) async {
    HapticFeedback.selectionClick();
    final canModify = MessageActionsService.canModify(data);
    final canEdit = mine && type == 'text' && canModify;
    final canDelete = mine && canModify;
    final canCopy = type == 'text' && text.isNotEmpty;
    final canReply = data['deletedAt'] == null && type != 'buzz';
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final reactions = (data['reactions'] as Map?)?.cast<String, dynamic>();
    final myReaction = (myUid != null) ? (reactions?[myUid] as String?) : null;

    // Compute the bubble's global rect so the overlay can anchor to it.
    final box = bubbleCtx.findRenderObject() as RenderBox?;
    Rect anchor;
    if (box != null && box.hasSize && box.attached) {
      final origin = box.localToGlobal(Offset.zero);
      anchor = origin & box.size;
    } else {
      // Fallback: center of screen if the render box isn't available.
      final size = MediaQuery.sizeOf(context);
      anchor = Rect.fromLTWH(size.width / 2 - 1, size.height / 2 - 1, 2, 2);
    }

    final result = await showMessageActionsOverlay(
      context,
      anchor: anchor,
      mine: mine,
      canReply: canReply,
      canCopy: canCopy,
      canEdit: canEdit,
      canDelete: canDelete,
      myReaction: myReaction,
    );
    if (result == null || !mounted) return;
    final connId = _connectionId;
    if (connId == null) return;

    if (result.reaction != null) {
      try {
        await MessageActionsService.setReaction(
          connectionId: connId,
          messageId: messageId,
          emoji: result.reaction!.isEmpty ? null : result.reaction,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reaction failed: $e')));
      }
      return;
    }
    switch (result.action) {
      case MessageAction.reply:
        _startReply(messageId, data);
        break;
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied'),
            duration: Duration(seconds: 1),
          ),
        );
        break;
      case MessageAction.edit:
        _startEdit(messageId, data);
        break;
      case MessageAction.deleteForEveryone:
        try {
          await MessageActionsService.deleteForEveryone(
            connectionId: connId,
            messageId: messageId,
            data: data,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        }
        break;
      case null:
        break;
    }
  }

  /// Open a fullscreen viewer focused on tile [initialIndex] with pinch to
  /// zoom. Swipe horizontally between siblings via PageView.
  void _openImageViewer(List<Map> images, int initialIndex) {
    if (images.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) {
        final controller = PageController(initialPage: initialIndex);
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                controller: controller,
                itemCount: images.length,
                itemBuilder: (_, i) {
                  final url = images[i]['url'] as String?;
                  if (url == null) return const SizedBox.shrink();
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar(NexaryoColors c) {
    return ValueListenableBuilder<bool?>(
      valueListenable: _connected,
      builder: (context, connected, _) {
        // Only show the disconnected pill once we've explicitly confirmed
        // (snapshot returned !exists). Until then, render the normal bar so
        // there's no "not connected" flash on entry.
        if (connected == false) return _buildDisconnectedBar(c);
        return ValueListenableBuilder<bool>(
          valueListenable: _isRecording,
          builder: (context, recording, _) {
            if (recording) return _buildRecordingBar(c);
            return _buildNormalInputBar(c);
          },
        );
      },
    );
  }

  Widget _buildDisconnectedBar(NexaryoColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.cardBorder),
        ),
        child: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedUserRemove01,
              color: c.textDim,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "You're not connected with ${_partnerName ?? 'this user'} anymore.",
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
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
              onPressed: _pickAndSendImages,
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
  final _PendingImage? pendingImage;
  final DateTime time;
  _ChatItem._(this.doc, this.pending, this.pendingImage, this.time);
  factory _ChatItem.doc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    DateTime t,
  ) => _ChatItem._(d, null, null, t);
  factory _ChatItem.pending(_PendingVoice p, DateTime t) =>
      _ChatItem._(null, p, null, t);
  factory _ChatItem.pendingImage(_PendingImage p, DateTime t) =>
      _ChatItem._(null, null, p, t);
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

/// Local placeholder for an image message that's still uploading. The real
/// Firestore doc lands later via the messages stream and replaces this in
/// the merged list (matched by [messageId]).
class _PendingImage {
  final String id;
  final int count;
  final List<XFile> previews;
  final DateTime createdAt;
  String? messageId;
  bool failed;
  _PendingImage({required this.id, required this.previews})
    : count = previews.length,
      createdAt = DateTime.now(),
      failed = false;
}

/// Composer-side draft of an outgoing reply. Holds the original message's
/// id, author, type and (for text) a short preview, plus the pre-built
/// payload map ready to attach as the new message's `replyTo` field.
class _ReplyDraft {
  final String messageId;
  final String fromUid;
  final String type;
  final String? preview;
  final Map<String, dynamic> payload;
  const _ReplyDraft({
    required this.messageId,
    required this.fromUid,
    required this.type,
    required this.preview,
    required this.payload,
  });
}

/// Wraps a chat bubble with a horizontal-drag-to-reply gesture. Dragging
/// right by more than [_triggerThreshold] and releasing fires [onReply].
/// Below that threshold the bubble springs back. A small reply icon
/// fades in behind the bubble while dragging so the affordance is
/// discoverable.
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  final Color accent;
  const _SwipeToReply({
    required this.child,
    required this.onReply,
    required this.enabled,
    required this.accent,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  /// Pixel offset past which a release triggers the reply.
  static const double _triggerThreshold = 56.0;

  /// Soft cap on how far the bubble can be dragged.
  static const double _maxDrag = 96.0;

  late final AnimationController _spring;
  Animation<double>? _springAnim;
  double _dx = 0;
  bool _crossed = false;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    // Only react to rightward drag. If the user drags left past 0 we
    // clamp to 0 so the bubble can't swing the wrong direction.
    final next = (_dx + d.delta.dx).clamp(0.0, _maxDrag);
    if (!_crossed && next >= _triggerThreshold) {
      _crossed = true;
      HapticFeedback.lightImpact();
    } else if (_crossed && next < _triggerThreshold) {
      _crossed = false;
    }
    setState(() => _dx = next);
  }

  void _onEnd(DragEndDetails d) {
    if (!widget.enabled) {
      _animateBack();
      return;
    }
    final triggered = _dx >= _triggerThreshold;
    _animateBack();
    if (triggered) widget.onReply();
  }

  void _animateBack() {
    _springAnim =
        Tween<double>(begin: _dx, end: 0).animate(
          CurvedAnimation(parent: _spring, curve: Curves.easeOutCubic),
        )..addListener(() {
          setState(() => _dx = _springAnim!.value);
        });
    _spring
      ..reset()
      ..forward();
    _crossed = false;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dx / _triggerThreshold).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _animateBack,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Reply hint icon revealed behind the bubble as it slides right.
          if (_dx > 4)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * progress,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedArrowTurnBackward,
                            color: widget.accent,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
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
  late AudioPlayer _player;
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
                  builder: (innerCtx) {
                    // Capture the down position then commit the seek only
                    // on `onTapUp` (a confirmed tap). Using `onTapDown`
                    // here would scrub on the very first touch and starve
                    // the parent _SwipeToReply of its horizontal-drag
                    // gesture — which is why voice bubbles previously
                    // felt un-swipeable.
                    Offset? downPos;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => downPos = d.localPosition,
                      onTapCancel: () => downPos = null,
                      onTapUp: (d) async {
                        final pos = downPos ?? d.localPosition;
                        downPos = null;
                        if (!_ready || total.inMilliseconds == 0) return;
                        final box = innerCtx.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final ratio = (pos.dx / box.size.width).clamp(0.0, 1.0);
                        await _player.seek(
                          Duration(
                            milliseconds: (total.inMilliseconds * ratio)
                                .round(),
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
                    );
                  },
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

class _BuzzPopup extends StatefulWidget {
  final ValueListenable<int> displayCount;
  final ValueListenable<bool?> connected;
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
  State<_BuzzPopup> createState() => _BuzzPopupState();
}

class _BuzzPopupState extends State<_BuzzPopup> {
  /// Auto-close after this much idle time. Matches the buzz flush
  /// window so the user sees their final batch leave before the popup
  /// disappears.
  static const Duration _idleClose = Duration(seconds: 5);

  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    widget.displayCount.addListener(_onActivity);
    widget.sentLabels.addListener(_onActivity);
    _resetIdle();
  }

  @override
  void dispose() {
    widget.displayCount.removeListener(_onActivity);
    widget.sentLabels.removeListener(_onActivity);
    _idleTimer?.cancel();
    super.dispose();
  }

  void _onActivity() => _resetIdle();

  void _resetIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleClose, _autoClose);
  }

  void _autoClose() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _handleTap() {
    widget.onTap();
    // _onActivity already fires via the displayCount listener, but reset
    // here too in case the count is briefly unchanged (e.g. after a
    // server snapshot rolls back local pending count).
    _resetIdle();
  }

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
                    ValueListenableBuilder<bool?>(
                      valueListenable: widget.connected,
                      builder: (_, conn, __) {
                        final isConnected = conn != false;
                        return Text(
                          isConnected
                              ? 'Buzzing ${widget.partnerName ?? "partner"}'
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
                    ValueListenableBuilder<bool?>(
                      valueListenable: widget.connected,
                      builder: (_, conn, __) {
                        final isConnected = conn != false;
                        return Material(
                          color: isConnected
                              ? c.primary
                              : c.primary.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(100),
                          child: InkWell(
                            onTap: isConnected ? _handleTap : null,
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
                                    valueListenable: widget.displayCount,
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
                valueListenable: widget.sentLabels,
                builder: (_, labels, __) {
                  return Stack(
                    children: [
                      for (final k in labels)
                        _SentFloat(
                          key: ValueKey(k),
                          color: c.primary,
                          onComplete: () => widget.onLabelComplete(k),
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
  late AnimationController _controller;
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

/// Renders 1\u20134 image tiles in a chat bubble layout matching common
/// messaging apps. Accepts entries with either `localPath` (pending) or
/// `url` (uploaded). Tap dispatches to [onTap] with the tile index.
class _ImageGrid extends StatelessWidget {
  final List<Map> images;
  final void Function(int index)? onTap;
  const _ImageGrid({required this.images, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final n = images.length;
    const radius = 14.0;
    const gap = 3.0;
    // Use the actual incoming constraint instead of MediaQuery math: the
    // bubble adds padding *and* a 1px border, so a width derived from the
    // screen drifts ~2px past the real available space and overflows the
    // Row. LayoutBuilder gives us exactly what the parent allotted.
    return LayoutBuilder(
      builder: (context, constraints) {
        // If the parent is unbounded (e.g. inside a scrollable), fall back
        // to a sensible default so we never produce infinite-width tiles.
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 240.0;
        final maxW = available.clamp(120.0, 320.0).floorToDouble();
        // Floor the half-tile too so 2*s + gap <= maxW exactly.
        final s = ((maxW - gap) / 2).floorToDouble();

        Widget tile(int i, {double? w, double? h}) {
          return _ImageTile(
            entry: images[i],
            width: w,
            height: h,
            onTap: onTap == null ? null : () => onTap!(i),
          );
        }

        Widget grid;
        if (n == 1) {
          grid = ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: tile(0, w: maxW, h: maxW),
          );
        } else if (n == 2) {
          grid = ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile(0, w: s, h: s),
                const SizedBox(width: gap),
                tile(1, w: s, h: s),
              ],
            ),
          );
        } else if (n == 3) {
          grid = ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile(0, w: s, h: maxW),
                const SizedBox(width: gap),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tile(1, w: s, h: s),
                    const SizedBox(height: gap),
                    tile(2, w: s, h: s),
                  ],
                ),
              ],
            ),
          );
        } else {
          // 4+: clamp to first 4 for the grid.
          grid = ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tile(0, w: s, h: s),
                    const SizedBox(width: gap),
                    tile(1, w: s, h: s),
                  ],
                ),
                const SizedBox(height: gap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tile(2, w: s, h: s),
                    const SizedBox(width: gap),
                    tile(3, w: s, h: s),
                  ],
                ),
              ],
            ),
          );
        }
        return grid;
      },
    );
  }
}

class _ImageTile extends StatelessWidget {
  final Map entry;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  const _ImageTile({required this.entry, this.width, this.height, this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = entry['url'] as String?;
    final localPath = entry['localPath'] as String?;
    Widget img;
    if (url != null && url.isNotEmpty) {
      img = Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, p) => p == null
            ? child
            : Container(
                width: width,
                height: height,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.black26,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.white70),
        ),
      );
    } else if (localPath != null) {
      img = Image.file(
        File(localPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    } else {
      img = Container(width: width, height: height, color: Colors.black26);
    }
    return GestureDetector(onTap: onTap, child: img);
  }
}

/// Quoted-message chip rendered at the top of a bubble whose `replyTo`
/// field is set. Layout: a tinted vertical accent bar + author name +
/// short preview line, with a type icon for non-text originals.
class _ReplyChip extends StatelessWidget {
  final NexaryoColors c;
  final bool mine;
  final Map<String, dynamic> replyTo;
  final String? myUid;
  final String? partnerName;
  const _ReplyChip({
    required this.c,
    required this.mine,
    required this.replyTo,
    required this.myUid,
    required this.partnerName,
  });

  /// HugeIcon glyph for a given original message type, or null for plain
  /// text (no leading icon needed in that case).
  List<List<dynamic>>? _iconFor(String type) {
    switch (type) {
      case 'image':
        return HugeIcons.strokeRoundedImage02;
      case 'voice':
        return HugeIcons.strokeRoundedMic01;
      case 'call':
        return HugeIcons.strokeRoundedCall;
      default:
        return null;
    }
  }

  /// Plain preview text (no emoji prefix — the icon carries that role).
  String _previewFor(String type) {
    switch (type) {
      case 'image':
        return 'Photo';
      case 'voice':
        return 'Voice message';
      case 'call':
        return 'Call';
      default:
        return 'Message';
    }
  }

  @override
  Widget build(BuildContext context) {
    final origFromUid = replyTo['fromUid'] as String?;
    final origType = (replyTo['type'] as String?) ?? 'text';
    final origMine = origFromUid != null && origFromUid == myUid;
    final author = origMine ? 'You' : (partnerName ?? 'Them');
    final rawPreview = replyTo['preview'] as String?;
    final preview = (rawPreview != null && rawPreview.isNotEmpty)
        ? rawPreview
        : _previewFor(origType);
    final typeIcon = _iconFor(origType);

    // On "mine" bubbles the bg is c.primary, so the chip lives on a
    // translucent white veneer; on "theirs" we use a faint primary tint.
    final bg = mine
        ? Colors.white.withValues(alpha: 0.16)
        : c.primary.withValues(alpha: 0.08);
    final authorColor = mine ? Colors.white : c.primary;
    final previewColor = mine
        ? Colors.white.withValues(alpha: 0.85)
        : c.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            author,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: authorColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (typeIcon != null) ...[
                HugeIcon(icon: typeIcon, color: previewColor, size: 13),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    color: previewColor,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aggregates [reactions] (uid \u2192 emoji) into emoji \u2192 count chips
/// shown beneath a bubble. Tap re-opens the action sheet.
class _ReactionBadges extends StatelessWidget {
  final NexaryoColors c;
  final bool mine;
  final Map<String, dynamic> reactions;
  final VoidCallback onTap;
  const _ReactionBadges({
    required this.c,
    required this.mine,
    required this.reactions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final v in reactions.values) {
      if (v is String && v.isNotEmpty) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Wrap(
        spacing: 4,
        children: [
          for (final entry in counts.entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 13)),
                  if (entry.value > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${entry.value}',
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Renders [text] with any embedded URLs as tappable underlined spans.
///
/// The detector matches:
///   * explicit schemes  — `http://`, `https://`, `mailto:`, `tel:`
///   * scheme-less hosts — `example.com`, `www.example.com/path?x=1`
///
/// Tapping launches the link via `url_launcher` in the platform's
/// default external app (browser / mail / dialer).
class _LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  const _LinkifiedText({
    required this.text,
    required this.style,
    required this.linkColor,
  });

  // One pass over the text. Single regex with two alternations so the
  // engine handles ordering for us. `\b` and a no-trailing-punct trick
  // keep us from swallowing the comma/period right after a URL.
  static final RegExp _urlRegex = RegExp(
    r'((?:https?:\/\/|mailto:|tel:)[^\s<>"]+|(?:www\.)?[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+(?:\/[^\s<>"]*)?)',
    caseSensitive: false,
  );

  /// Trim trailing punctuation that humans almost never mean to include
  /// in a URL (period at end of a sentence, closing bracket, etc.).
  static String _trimTrailingPunct(String url) {
    const trailing = '.,;:!?)]}>\'"';
    var end = url.length;
    while (end > 0 && trailing.contains(url[end - 1])) {
      end--;
    }
    return url.substring(0, end);
  }

  /// Resolve a matched span to a launchable URI. Returns null for
  /// strings that look url-ish but don't actually have a host (e.g. a
  /// stray `1.2`).
  static Uri? _resolve(String raw) {
    final s = _trimTrailingPunct(raw);
    if (s.isEmpty) return null;
    if (s.startsWith('mailto:') || s.startsWith('tel:')) {
      return Uri.tryParse(s);
    }
    final withScheme = s.startsWith('http://') || s.startsWith('https://')
        ? s
        : 'https://$s';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      return null;
    }
    return uri;
  }

  Future<void> _open(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Show a safety confirmation before launching. Discloses the full
  /// resolved URL so the user can spot phishing / typo-squatted hosts
  /// before opening. Auto-launches only on user confirmation.
  Future<void> _confirmAndOpen(BuildContext context, Uri uri) async {
    final c = context.colors;
    final shown = uri.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.cardBorder),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAlert02,
              color: c.primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              'Open external link?',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to leave Buzz Bee. Make sure you trust this address before continuing.',
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: c.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.cardBorder),
              ),
              child: SelectableText(
                shown,
                style: GoogleFonts.firaCode(
                  fontSize: 12.5,
                  color: c.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Open',
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.primary,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _open(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _urlRegex.allMatches(text).toList(growable: false);
    if (matches.isEmpty) {
      return Text(text, style: style);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    final linkStyle = style.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
    for (final m in matches) {
      final raw = text.substring(m.start, m.end);
      final trimmed = _trimTrailingPunct(raw);
      final uri = _resolve(raw);
      // Length of the matched URL minus the trailing punctuation that
      // we DON'T want to underline / make tappable.
      final linkLen = trimmed.length;
      // Plain text before the match.
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      if (uri == null) {
        // Looked URL-ish but didn't resolve — render as plain text.
        spans.add(TextSpan(text: raw));
      } else {
        spans.add(
          TextSpan(
            text: text.substring(m.start, m.start + linkLen),
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _confirmAndOpen(context, uri),
          ),
        );
        // Trailing punctuation that we trimmed off goes back as plain.
        if (linkLen < raw.length) {
          spans.add(TextSpan(text: text.substring(m.start + linkLen, m.end)));
        }
      }
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
