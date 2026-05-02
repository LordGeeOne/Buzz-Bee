import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show navigatorKey;
import '../screens/dashboard_screen.dart';
import '../theme/nexaryo_colors.dart';

/// Wraps the app and listens to the signed-in user's `notifications`
/// collection for unread `match` documents. When one appears, surfaces a
/// celebratory popup with the partner's name + photo and a "View my
/// matches" button that routes to the dashboard.
///
/// Both sides of a match get the popup:
///   * UserA (first liker) — when their app is foregrounded after UserB
///     accepts.
///   * UserB (second liker) — almost immediately after their tap, since
///     `acceptRequest` writes a self-notification too.
class MatchOverlay extends StatefulWidget {
  final Widget child;
  const MatchOverlay({super.key, required this.child});

  @override
  State<MatchOverlay> createState() => _MatchOverlayState();
}

class _MatchOverlayState extends State<MatchOverlay> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<User?>? _authSub;
  // Notification doc ids we've already displayed (or are mid-display) — keeps
  // us from re-showing the dialog if the snapshot fires twice before the
  // `read` flag round-trips.
  final Set<String> _shownIds = <String>{};
  // True while a match dialog is on screen, so a second match arriving in
  // quick succession queues instead of stacking.
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _bind(FirebaseAuth.instance.currentUser);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_bind);
  }

  void _bind(User? user) {
    _sub?.cancel();
    _sub = null;
    _shownIds.clear();
    if (user == null) return;
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('type', isEqualTo: 'match')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen(_onSnap);
  }

  void _onSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_showing) return;
    for (final d in snap.docs) {
      if (_shownIds.contains(d.id)) continue;
      // Only one popup at a time; the next snapshot tick (after the user
      // dismisses + we mark read) will surface the next one.
      _present(d);
      break;
    }
  }

  Future<void> _present(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      // Navigator not ready yet (cold start). Don't mark this id as shown
      // — the next snapshot tick after the navigator mounts will surface
      // it. Schedule a single retry on the next frame as a safety net.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_showing) _present(doc);
      });
      return;
    }
    // Reserve the id NOW so a re-fire of the same snapshot doesn't
    // double-present the same doc.
    _shownIds.add(doc.id);
    final data = doc.data();
    final name = (data['fromName'] as String?)?.trim();
    final photo = (data['fromPhoto'] as String?) ?? '';

    _showing = true;
    try {
      await showGeneralDialog<void>(
        context: ctx,
        barrierDismissible: true,
        barrierLabel: 'Date',
        barrierColor: Colors.black.withValues(alpha: 0.6),
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => _MatchDialog(
          partnerName: (name == null || name.isEmpty) ? 'Someone new' : name,
          partnerPhoto: photo,
        ),
        transitionBuilder: (_, anim, __, child) {
          final scale = Tween<double>(
            begin: 0.85,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeOutBack)).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: scale, child: child),
          );
        },
      );
    } finally {
      _showing = false;
    }

    // Mark as read so the listener doesn't keep re-firing on it.
    try {
      await doc.reference.update({'read': true});
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MatchDialog extends StatelessWidget {
  final String partnerName;
  final String partnerPhoto;
  const _MatchDialog({required this.partnerName, required this.partnerPhoto});

  void _viewMatches(BuildContext context) {
    // Close the dialog first.
    Navigator.of(context, rootNavigator: true).maybePop();
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<NexaryoColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(28),
          elevation: 12,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "It's a date!",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'You and $partnerName sparked each other',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.card,
                    border: Border.all(color: c.primary, width: 3),
                    image: partnerPhoto.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(partnerPhoto),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: partnerPhoto.isEmpty
                      ? Icon(Icons.person, size: 56, color: c.textSecondary)
                      : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _viewMatches(context),
                    child: Text(
                      'View my Hive',
                      style: GoogleFonts.montserrat(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).maybePop(),
                  child: Text(
                    'Keep swiping',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
