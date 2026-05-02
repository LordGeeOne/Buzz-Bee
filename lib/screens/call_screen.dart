import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../services/call_service.dart';
import '../theme/nexaryo_colors.dart';
import '../widgets/call_banner_overlay.dart';
import 'chat_screen.dart';

/// Full-screen 1:1 voice call UI.
///
/// Outgoing path: pushed by ChatScreen after `CallService.startCall(...)`.
/// Incoming path: pushed by CallkitService on accept after answerCall(...).
class CallScreen extends StatefulWidget {
  final String callId;
  final String connectionId;
  final String peerUid;
  final String peerName;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.callId,
    required this.connectionId,
    required this.peerUid,
    required this.peerName,
    required this.isIncoming,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<CallSession?>? _sub;
  CallSession? _session;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  DateTime? _connectedAt;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    isCallScreenForeground.value = true;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _session = CallService.instance.current;
    _connectedAt = CallService.instance.connectedAt;
    _sub = CallService.instance.sessionStream.listen((s) {
      if (!mounted) return;
      final wasConnected = _connectedAt != null;
      if (s?.state == 'connected' && !wasConnected) {
        _connectedAt = CallService.instance.connectedAt ?? DateTime.now();
        _startTicker();
      }
      setState(() => _session = s);
      if (s == null) {
        _exitToChat();
      }
    });
    if (_connectedAt != null) {
      _elapsed = DateTime.now().difference(_connectedAt!);
      _startTicker();
    }
  }

  void _exitToChat() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(partnerUid: widget.peerUid),
        ),
      );
    }
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
    isCallScreenForeground.value = false;
    _sub?.cancel();
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String _fmtElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _statusLine() {
    final s = _session;
    if (s == null) return 'Call ended';
    switch (s.state) {
      case 'ringing':
        return widget.isIncoming ? 'Incoming voice call' : 'Ringing…';
      case 'accepted':
        return 'Connecting…';
      case 'connected':
        return _fmtElapsed(_elapsed);
      case 'failed':
        return "Couldn't connect — try a different network";
      case 'declined':
        return 'Declined';
      case 'missed':
        return 'No answer';
      case 'ended':
      default:
        return 'Call ended';
    }
  }

  bool get _isRinging =>
      _session?.state == 'ringing' || _session?.state == 'accepted';

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<NexaryoColors>()!;
    final s = _session;
    final muted = s?.muted ?? false;
    final speaker = s?.speakerOn ?? false;
    final isConnected = s?.state == 'connected';

    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              c.primary.withValues(alpha: 0.22),
              c.background,
              c.background,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Minimize',
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).maybePop();
                        } else {
                          _exitToChat();
                        }
                      },
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        color: c.textDim,
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedCall02,
                            color: c.primary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Buzz Bee · voice',
                            style: GoogleFonts.montserrat(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.peerName.isEmpty ? 'Buzz Bee' : widget.peerName,
                  style: TextStyle(
                    fontFamily: 'Beli',
                    fontSize: 44,
                    color: c.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? c.primary.withValues(alpha: 0.12)
                        : c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isConnected
                          ? c.primary.withValues(alpha: 0.4)
                          : c.cardBorder,
                    ),
                  ),
                  child: Text(
                    _statusLine(),
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: isConnected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isConnected ? c.primary : c.textDim,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const Spacer(),
                _Avatar(
                  pulse: _pulse,
                  pulsing: _isRinging,
                  name: widget.peerName,
                  colors: c,
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: muted
                          ? HugeIcons.strokeRoundedMicOff01
                          : HugeIcons.strokeRoundedMic01,
                      label: muted ? 'Unmute' : 'Mute',
                      active: muted,
                      colors: c,
                      onTap: () => CallService.instance.setMuted(!muted),
                    ),
                    _EndCallButton(
                      onTap: () async {
                        await CallService.instance.endCall();
                        if (mounted) {
                          _exitToChat();
                        }
                      },
                    ),
                    _CallActionButton(
                      icon: speaker
                          ? HugeIcons.strokeRoundedVolumeHigh
                          : HugeIcons.strokeRoundedVolumeLow,
                      label: speaker ? 'Speaker' : 'Earpiece',
                      active: speaker,
                      colors: c,
                      onTap: () => CallService.instance.setSpeakerOn(!speaker),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final AnimationController pulse;
  final bool pulsing;
  final String name;
  final NexaryoColors colors;

  const _Avatar({
    required this.pulse,
    required this.pulsing,
    required this.name,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (pulsing)
            AnimatedBuilder(
              animation: pulse,
              builder: (_, __) {
                final t = pulse.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [_ring(t, c), _ring((t + 0.5) % 1.0, c)],
                );
              },
            ),
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.primary.withValues(alpha: 0.35),
                  c.primary.withValues(alpha: 0.15),
                ],
              ),
              border: Border.all(color: c.primary, width: 3),
              boxShadow: [
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: GoogleFonts.montserrat(
                  fontSize: 80,
                  fontWeight: FontWeight.w700,
                  color: c.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double t, NexaryoColors c) {
    final size = 180.0 + (70.0 * t);
    final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.45;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: c.primary.withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final dynamic icon;
  final String label;
  final bool active;
  final NexaryoColors colors;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final bg = active ? c.primary : c.surface;
    final fg = active ? Colors.white : c.textPrimary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          elevation: active ? 4 : 0,
          shadowColor: c.primary.withValues(alpha: 0.4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? Colors.transparent : c.cardBorder,
                ),
              ),
              child: Center(
                child: HugeIcon(icon: icon, color: fg, size: 26),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.textDim,
          ),
        ),
      ],
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: const Color(0xFFE53935),
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: const Color(0xFFE53935).withValues(alpha: 0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 78,
              height: 78,
              child: Transform.rotate(
                angle: 2.356, // ~135° → "hung up" handset look
                child: const Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedCall02,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'End',
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE53935),
          ),
        ),
      ],
    );
  }
}
