import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../services/connection_service.dart';
import '../services/user_cache.dart';
import '../theme/nexaryo_colors.dart';
import 'profile_screen.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen>
    with TickerProviderStateMixin {
  // Deck
  List<Map<String, dynamic>> _deck = [];
  bool _loadingDeck = true;

  // UIDs of people who already sent me a request (a like from them).
  // A like from me to one of these will accept (forming a connection).
  Set<String> _incomingLikes = <String>{};

  // UIDs I've already liked this session — used to avoid duplicate Firestore
  // writes (the request doc is overwritten anyway, but `notifications` uses
  // `.add()` and would create a new doc per tap).
  final Set<String> _outgoingLikes = <String>{};

  // Drag state
  Offset _drag = Offset.zero;
  bool _animatingOut = false;

  late AnimationController _swipeCtrl;
  Animation<Offset> _swipeAnim = const AlwaysStoppedAnimation(Offset.zero);

  late AnimationController _resetCtrl;
  Animation<Offset> _resetAnim = const AlwaysStoppedAnimation(Offset.zero);

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _swipeCtrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 260),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed) _onSwipeAnimationComplete();
        });

    _resetCtrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          setState(() => _drag = _resetAnim.value);
        });

    _loadDeck();
  }

  @override
  void dispose() {
    _swipeCtrl.dispose();
    _resetCtrl.dispose();
    super.dispose();
  }

  // ---------------- Data ----------------

  Future<void> _loadDeck() async {
    setState(() => _loadingDeck = true);
    // Fresh deck → forget which uids we've liked this session so the user
    // can re-like after a manual refresh if something went wrong.
    _outgoingLikes.clear();
    try {
      final fs = FirebaseFirestore.instance;

      // Run the three independent reads in parallel.
      final results = await Future.wait([
        fs.collection('users').doc(_myUid).collection('requests').get(),
        fs
            .collection('connections')
            .where('users', arrayContains: _myUid)
            .get(),
        fs.collection('users').limit(60).get(),
      ]);
      final reqSnap = results[0];
      final connSnap = results[1];
      final usersSnap = results[2];

      final incomingUids = reqSnap.docs.map((d) => d.id).toSet();

      final connectedUids = <String>{};
      for (final d in connSnap.docs) {
        final users = ((d.data()['users'] as List?) ?? const []).cast<String>();
        for (final u in users) {
          if (u != _myUid) connectedUids.add(u);
        }
      }

      final priority = <Map<String, dynamic>>[];
      final rest = <Map<String, dynamic>>[];
      for (final d in usersSnap.docs) {
        if (d.id == _myUid) continue;
        if (connectedUids.contains(d.id)) continue;
        final entry = {'uid': d.id, ...d.data()};
        if (incomingUids.contains(d.id)) {
          priority.add(entry);
        } else {
          rest.add(entry);
        }
      }

      // 4) Hydrate any incoming-request senders missing from the user batch.
      final present = {for (final u in priority) u['uid'] as String};
      final missing = incomingUids
          .difference(present)
          .difference(connectedUids)
          .difference({_myUid});
      for (final uid in missing) {
        try {
          final u = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          if (u.exists) {
            priority.add({'uid': uid, ...?u.data()});
          }
        } catch (_) {}
      }

      rest.shuffle();
      if (!mounted) return;
      setState(() {
        _incomingLikes = incomingUids;
        _deck = [...priority, ...rest];
        _loadingDeck = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDeck = false);
    }
  }

  /// A right swipe / tap on the heart. If this person already liked me,
  /// accept the request (forming a connection). Otherwise send a like.
  Future<void> _likeUser(String otherUid) async {
    final isMutual = _incomingLikes.contains(otherUid);
    // Already liked this session and they haven't liked back — tell the
    // user instead of silently dropping the tap.
    if (!isMutual && _outgoingLikes.contains(otherUid)) {
      _toast('Already sparked');
      return;
    }
    try {
      if (isMutual) {
        await ConnectionService.acceptRequest(otherUid);
        if (!mounted) return;
        _incomingLikes.remove(otherUid);
        _outgoingLikes.remove(otherUid);
        _toast("It's a date! ✨");
      } else {
        await ConnectionService.sendRequest(otherUid);
        if (!mounted) return;
        _outgoingLikes.add(otherUid);
        _toast('Spark sent');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : 'Something went wrong';
      _toast(msg);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.montserrat()),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // ---------------- Swipe ----------------

  void _onPanUpdate(DragUpdateDetails d) {
    if (_animatingOut) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_animatingOut) return;
    final w = MediaQuery.of(context).size.width;
    final threshold = w * 0.28;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (_drag.dx > threshold || vx > 800) {
      _flyOut(true);
    } else if (_drag.dx < -threshold || vx < -800) {
      _flyOut(false);
    } else {
      _resetAnim = Tween<Offset>(
        begin: _drag,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOutBack));
      _resetCtrl
        ..reset()
        ..forward();
    }
  }

  void _flyOut(bool right) {
    if (_deck.isEmpty) return;
    final w = MediaQuery.of(context).size.width;
    final end = Offset(right ? w * 1.6 : -w * 1.6, _drag.dy + 60);
    _swipeAnim = Tween<Offset>(begin: _drag, end: end).animate(
      CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOut),
    )..addListener(_onSwipeTick);
    setState(() => _animatingOut = true);
    if (right) _likeUser(_deck.first['uid']);
    _swipeCtrl
      ..reset()
      ..forward();
  }

  void _onSwipeTick() => setState(() => _drag = _swipeAnim.value);

  void _onSwipeAnimationComplete() {
    _swipeAnim.removeListener(_onSwipeTick);
    setState(() {
      if (_deck.isNotEmpty) _deck.removeAt(0);
      _drag = Offset.zero;
      _animatingOut = false;
    });
  }

  void _buttonSwipe(bool right) {
    if (_animatingOut || _deck.isEmpty) return;
    _flyOut(right);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: c.background,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Full-bleed deck
          Positioned.fill(child: _buildDeck(c)),
          // Top gradient for status bar legibility
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: topInset + 80,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          // Top bar
          Positioned(top: topInset, left: 0, right: 0, child: _buildTopBar(c)),
          // Bottom action row
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset,
            child: _buildActionRow(c),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(NexaryoColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          _topBtn(
            c,
            icon: HugeIcons.strokeRoundedArrowLeft01,
            onTap: () => Navigator.pop(context),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _topBtn(
    NexaryoColors c, {
    required List<List<dynamic>> icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 68,
      height: 68,
      child: IconButton(
        icon: HugeIcon(icon: icon, color: c.textDim, size: 24),
        onPressed: onTap,
      ),
    );
  }

  // ---------------- Deck ----------------

  Widget _buildDeck(NexaryoColors c) {
    if (_loadingDeck) {
      return Center(child: CircularProgressIndicator(color: c.primary));
    }
    if (_deck.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedUserGroup,
              color: c.cardBorder,
              size: 56,
            ),
            const SizedBox(height: 14),
            Text(
              "That's everyone for now",
              style: GoogleFonts.montserrat(
                fontSize: 15,
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _loadDeck,
              child: Text(
                'Check again',
                style: GoogleFonts.montserrat(
                  color: c.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final visible = _deck.take(3).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.center,
          children: [
            for (int i = visible.length - 1; i >= 0; i--)
              _buildCard(c, visible[i], i, constraints),
          ],
        );
      },
    );
  }

  Widget _buildCard(
    NexaryoColors c,
    Map<String, dynamic> user,
    int index,
    BoxConstraints constraints,
  ) {
    final isTop = index == 0;
    final width = constraints.maxWidth;
    final progress = isTop ? (_drag.dx / (width * 0.6)).clamp(-1.0, 1.0) : 0.0;
    final angle = isTop ? progress * 0.18 : 0.0;

    final scale = isTop ? 1.0 : 1.0 - (index * 0.04);
    final yOffset = isTop ? 0.0 : index * 12.0;

    Widget card = _CardContent(user: user, swipeProgress: progress);

    if (isTop) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Transform.translate(
          offset: _drag,
          child: Transform.rotate(angle: angle, child: card),
        ),
      );
    } else {
      card = IgnorePointer(
        child: Transform.translate(
          offset: Offset(0, yOffset),
          child: Transform.scale(scale: scale, child: card),
        ),
      );
    }

    return Positioned.fill(child: card);
  }

  Widget _buildActionRow(NexaryoColors c) {
    final disabled = _deck.isEmpty || _animatingOut;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionBtn(
            c,
            icon: HugeIcons.strokeRoundedCancel01,
            color: c.accentWarm,
            onTap: disabled ? null : () => _buttonSwipe(false),
          ),
          _actionBtn(
            c,
            icon: HugeIcons.strokeRoundedFavourite,
            color: c.primary,
            onTap: disabled ? null : () => _buttonSwipe(true),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    NexaryoColors c, {
    required List<List<dynamic>> icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    const size = 68.0;
    const iconSize = 28.0;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: onTap == null ? 0.4 : 1.0,
      child: Material(
        color: Color.alphaBlend(color.withValues(alpha: 0.22), c.card),
        shape: CircleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.55), width: 1.5),
        ),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: HugeIcon(icon: icon, color: color, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardContent extends StatefulWidget {
  const _CardContent({required this.user, required this.swipeProgress});

  final Map<String, dynamic> user;
  final double swipeProgress;

  @override
  State<_CardContent> createState() => _CardContentState();
}

class _CardContentState extends State<_CardContent> {
  int _imgIndex = 0;

  List<String> get _images {
    final imgs = <String>[];
    final gallery = widget.user['gallery'];
    if (gallery is List) {
      for (final g in gallery) {
        if (g is String && g.isNotEmpty) imgs.add(g);
      }
    }
    return imgs;
  }

  void _next() {
    final imgs = _images;
    if (imgs.length <= 1) return;
    setState(() => _imgIndex = (_imgIndex + 1) % imgs.length);
  }

  void _prev() {
    final imgs = _images;
    if (imgs.length <= 1) return;
    setState(() => _imgIndex = (_imgIndex - 1 + imgs.length) % imgs.length);
  }

  void _openProfile(BuildContext context, Map<String, dynamic> user) {
    final uid = user['uid'] as String?;
    if (uid == null || uid.isEmpty) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = widget.user;
    final swipeProgress = widget.swipeProgress;
    final images = _images;
    final currentPhoto = images.isNotEmpty ? images[_imgIndex] : '';
    final name = (user['name'] as String?) ?? 'User';
    final username = (user['username'] as String?) ?? '';
    final bio = (user['bio'] as String?) ?? '';
    final age = _calcAge(user['dob']);

    final likeOpacity = swipeProgress.clamp(0.0, 1.0);
    final passOpacity = (-swipeProgress).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(color: c.card),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (currentPhoto.isNotEmpty)
            Image(
              image: UserCache.avatarFor(currentPhoto),
              key: ValueKey(currentPhoto),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _placeholder(c),
            )
          else
            _placeholder(c),
          // Pagination dots
          if (images.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  for (int i = 0; i < images.length; i++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 3,
                        decoration: BoxDecoration(
                          color: i == _imgIndex
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xE6000000),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Name + age + @handle bundle is tappable and opens the
                // user's profile. Sits above the image-tap zones because
                // it's later in the parent Stack's child order.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openProfile(context, user),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Beli',
                                fontSize: 26,
                                height: 1.1,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (age != null) ...[
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '$age',
                                style: GoogleFonts.montserrat(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: GoogleFonts.montserrat(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // LIKE / PASS badges centered on the card.
          if (likeOpacity > 0 || passOpacity > 0)
            Center(
              child: Opacity(
                opacity: likeOpacity > 0 ? likeOpacity : passOpacity,
                child: Transform.rotate(
                  angle: likeOpacity > 0 ? -0.2 : 0.2,
                  child: _badge(
                    likeOpacity > 0 ? 'SPARK' : 'PASS',
                    likeOpacity > 0 ? c.primary : c.accentWarm,
                  ),
                ),
              ),
            ),
          // Tap zones for image navigation. Constrained to the upper part
          // of the card so they don't swallow taps on the name/profile
          // area below.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 200,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _prev,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(NexaryoColors c) {
    return Container(
      color: c.surface,
      child: Center(
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedUser,
          color: c.cardBorder,
          size: 80,
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: GoogleFonts.montserrat(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 44,
          letterSpacing: 4,
        ),
      ),
    );
  }

  int? _calcAge(dynamic dob) {
    try {
      DateTime? d;
      if (dob is Timestamp) {
        d = dob.toDate();
      } else if (dob is String && dob.isNotEmpty) {
        d = DateTime.tryParse(dob);
      }
      if (d == null) return null;
      final now = DateTime.now();
      var age = now.year - d.year;
      if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
        age--;
      }
      return age >= 0 ? age : null;
    } catch (_) {
      return null;
    }
  }
}
