import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../main.dart' show navigatorKey;
import '../screens/call_screen.dart';
import '../screens/chat_screen.dart';
import '../services/call_service.dart';
import '../theme/nexaryo_colors.dart';

/// Tracks whether the user is currently viewing the full-screen [CallScreen].
/// Set by `CallScreen` in initState/dispose so the banner can suppress
/// itself while the call UI is already on top.
final ValueNotifier<bool> isCallScreenForeground = ValueNotifier<bool>(false);

/// Wraps the app with a top banner that appears whenever a call is active
/// and the user is *not* on the call screen. Tapping the banner opens the
/// call screen.
class CallBannerOverlay extends StatefulWidget {
  final Widget child;
  const CallBannerOverlay({super.key, required this.child});

  @override
  State<CallBannerOverlay> createState() => _CallBannerOverlayState();
}

class _CallBannerOverlayState extends State<CallBannerOverlay> {
  StreamSubscription<CallSession?>? _sub;
  CallSession? _session;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  DateTime? _connectedAt;

  @override
  void initState() {
    super.initState();
    _session = CallService.instance.current;
    _connectedAt = CallService.instance.connectedAt;
    if (_connectedAt != null) {
      _elapsed = DateTime.now().difference(_connectedAt!);
      _startTicker();
    }
    _sub = CallService.instance.sessionStream.listen((s) {
      if (!mounted) return;
      if (s?.state == 'connected' && _connectedAt == null) {
        _connectedAt = CallService.instance.connectedAt ?? DateTime.now();
        _startTicker();
      }
      if (s == null) {
        _connectedAt = null;
        _ticker?.cancel();
        _elapsed = Duration.zero;
      }
      setState(() => _session = s);
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_connectedAt!));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _statusLabel(CallSession s) {
    switch (s.state) {
      case 'ringing':
        return s.isCaller ? 'Ringing…' : 'Incoming call';
      case 'accepted':
        return 'Connecting…';
      case 'connected':
        final m = _elapsed.inMinutes.toString().padLeft(2, '0');
        final sec = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
        return 'On call · $m:$sec';
      default:
        return 'In call';
    }
  }

  void _openCall(CallSession s) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: s.callId,
          connectionId: s.connectionId,
          peerUid: s.peerUid,
          peerName: s.peerName ?? '',
          isIncoming: !s.isCaller,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<NexaryoColors>();
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: isCallScreenForeground,
          builder: (_, onCallScreen, __) {
            final s = _session;
            if (s == null || onCallScreen || c == null) {
              return const SizedBox.shrink();
            }
            return _DraggableCallBanner(
              colors: c,
              session: s,
              statusLabel: _statusLabel(s),
              onTap: () => _openCall(s),
            );
          },
        ),
      ],
    );
  }
}

class _DraggableCallBanner extends StatefulWidget {
  final NexaryoColors colors;
  final CallSession session;
  final String statusLabel;
  final VoidCallback onTap;

  const _DraggableCallBanner({
    required this.colors,
    required this.session,
    required this.statusLabel,
    required this.onTap,
  });

  @override
  State<_DraggableCallBanner> createState() => _DraggableCallBannerState();
}

class _DraggableCallBannerState extends State<_DraggableCallBanner> {
  Offset? _offset; // null = use default top placement
  Size? _bannerSize;
  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final topInset = media.padding.top + 8;
    // Default position: just below status bar, centered horizontally.
    final defaultLeft = 12.0;
    final defaultTop = topInset;

    return Positioned(
      left: _offset?.dx ?? defaultLeft,
      top: _offset?.dy ?? defaultTop,
      right: _offset == null ? 12 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          final size = _bannerSize ?? const Size(280, 60);
          final cur = _offset ?? Offset(defaultLeft, defaultTop);
          var nx = cur.dx + d.delta.dx;
          var ny = cur.dy + d.delta.dy;
          nx = nx.clamp(8.0, screen.width - size.width - 8);
          ny = ny.clamp(media.padding.top, screen.height - size.height - 24);
          setState(() => _offset = Offset(nx, ny));
        },
        child: Material(
          key: _key,
          color: Colors.transparent,
          elevation: 12,
          shadowColor: c.primary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [c.primary, c.primary.withValues(alpha: 0.85)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: c.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Builder(
                  builder: (ctx) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final box =
                          _key.currentContext?.findRenderObject() as RenderBox?;
                      if (box != null && box.hasSize) {
                        _bannerSize = box.size;
                      }
                    });
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const HugeIcon(
                          icon: HugeIcons.strokeRoundedDragDropVertical,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          child: const Center(
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedCall02,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.session.peerName?.isNotEmpty == true
                                    ? widget.session.peerName!
                                    : 'Buzz Bee call',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.montserrat(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                widget.statusLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirmation dialog used by chat call-log bubbles to avoid mistaken
/// taps. Returns true when the user confirms the call.
Future<bool> showCallConfirmDialog(
  BuildContext context, {
  required String peerName,
}) async {
  final c = Theme.of(context).extension<NexaryoColors>()!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.cardBorder),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.primary.withValues(alpha: 0.15),
              ),
              child: Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCall02,
                  color: c.primary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Call ${peerName.isEmpty ? 'them' : peerName}?',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Start a free Buzz Bee voice call right now.',
          style: GoogleFonts.montserrat(fontSize: 13, color: c.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textDim,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HugeIcon(
                  icon: HugeIcons.strokeRoundedCall02,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Call',
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Push a [ChatScreen] for [partnerUid] using the root navigator.
void ensureChatScreenFor(String partnerUid) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  nav.push(
    MaterialPageRoute(builder: (_) => ChatScreen(partnerUid: partnerUid)),
  );
}
