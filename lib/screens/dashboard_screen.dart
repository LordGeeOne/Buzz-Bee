import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/connection_service.dart';
import '../theme/nexaryo_colors.dart';
import '../widgets/blob_background.dart';
import 'chat_screen.dart';
import 'people_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  bool _locationGranted = false;
  bool _notificationsGranted = false;
  bool _imagesUploaded = false;

  static const _sections = [
    _Section('Home', null),
    _Section('Buzz Bee', null),
    _Section('Buzz Pic', null),
    _Section('Buzz Word', null),
    _Section('Buzz Voice', null),
  ];

  // Back panel top content is roughly 120px (safe area + app name + subtitle).
  // We reserve that by capping maxChildSize so the front panel can't fully cover it.
  static const double _minSheet = 0.5;
  static const double _maxSheet = 0.82;
  static const double _initialSheet = 0.5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshChecklist();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sheetController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshChecklist();
    }
  }

  Future<void> _refreshChecklist() async {
    final loc = await Permission.locationWhenInUse.status;
    final notif = await Permission.notification.status;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var imagesUploaded = false;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final list = (doc.data()?['gallery'] as List?) ?? const [];
        imagesUploaded = list.whereType<String>().length >= _minGalleryToSearch;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _locationGranted = loc.isGranted || loc.isLimited;
      _notificationsGranted = notif.isGranted;
      _imagesUploaded = imagesUploaded;
    });
  }

  Future<void> _requestLocation() async {
    final status = await Permission.locationWhenInUse.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    _refreshChecklist();
  }

  Future<void> _requestNotifications() async {
    final status = await Permission.notification.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    _refreshChecklist();
  }

  Future<void> _uploadImages() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (!mounted) return;
    _refreshChecklist();
  }

  static const int _minGalleryToSearch = 3;

  Future<void> _startSearching() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    int galleryCount = 0;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final list = (doc.data()?['gallery'] as List?) ?? const [];
      galleryCount = list.whereType<String>().length;
    } catch (_) {
      // On lookup failure we still let the user proceed; the dialog is a
      // soft gate, not a security boundary.
    }

    if (!mounted) return;
    if (galleryCount < _minGalleryToSearch) {
      await _showAddPhotosDialog(galleryCount);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PeopleScreen()),
    );
  }

  Future<void> _showAddPhotosDialog(int currentCount) async {
    final c = context.colors;
    final missing = _minGalleryToSearch - currentCount;
    final more = missing == 1 ? '1 more photo' : '$missing more photos';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Show off your best photos'),
        content: Text(
          'A great profile starts with at least '
          '$_minGalleryToSearch photos. Just $more to go — let people see who you are!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Maybe later'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.primary),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: const Text('Add photos'),
          ),
        ],
      ),
    );
  }

  void _navigateHome() {
    setState(() => _currentIndex = 0);
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        _initialSheet,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Stack(
        children: [
          // Background color fills full screen behind front panel
          Container(color: c.background),
          // ── Back Panel ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.5,
            child: BlobBackground(
              jointColor: c.primary,
              background: c.background,
            ),
          ),
          // Glass overlay
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withOpacity(0.25)),
            ),
          ),
          _buildBackPanel(context),

          // ── Front Panel ──
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _initialSheet,
            minChildSize: _minSheet,
            maxChildSize: _maxSheet,
            snap: true,
            snapSizes: const [_initialSheet, _maxSheet],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(34),
                  ),
                ),
                child: Column(
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.cardBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Section title bar (inside front panel)
                    if (_currentIndex != 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Container(
                              height: 68,
                              width: 68,
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(34),
                              ),
                              child: IconButton(
                                icon: HugeIcon(
                                  icon: HugeIcons.strokeRoundedArrowLeft01,
                                  color: c.textDim,
                                  size: 24,
                                ),
                                iconSize: 24,
                                onPressed: _navigateHome,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _sections[_currentIndex].title,
                                style: GoogleFonts.montserrat(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: c.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Content
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: [
                          _buildCurrentPage(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Back Panel ──
  Widget _buildBackPanel(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: app name + settings
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Buzz Bee',
                  style: TextStyle(
                    fontFamily: 'Beli',
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Container(
                  height: 68,
                  width: 68,
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(34),
                  ),
                  child: IconButton(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedUserCircle,
                      color: c.textDim,
                      size: 24,
                    ),
                    iconSize: 24,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Ready when you are',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Your vibe',
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 10),
                ...List.generate(5, (i) {
                  const rating = 4; // placeholder rating out of 5
                  return Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: HugeIcon(
                      icon: i < rating
                          ? HugeIcons.strokeRoundedStar
                          : HugeIcons.strokeRoundedStar,
                      color: i < rating
                          ? c.accentWarm
                          : Colors.white.withValues(alpha: 0.25),
                      size: 18,
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _BackPanelButton(
                    label: 'Find people',
                    icon: HugeIcons.strokeRoundedSearch01,
                    filled: true,
                    onTap: _startSearching,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BackPanelButton(
                    label: 'Get verified',
                    icon: HugeIcons.strokeRoundedCheckmarkBadge01,
                    filled: false,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Verification is on the way — stay tuned!',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            if (!_locationGranted ||
                !_notificationsGranted ||
                !_imagesUploaded) ...[
              const SizedBox(height: 22),
              Text(
                'GET STARTED',
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 10),
              if (!_locationGranted)
                _ChecklistItem(
                  label: 'Allow location services',
                  checked: false,
                  onTap: _requestLocation,
                ),
              if (!_notificationsGranted)
                _ChecklistItem(
                  label: 'Turn on notifications',
                  checked: false,
                  onTap: _requestNotifications,
                ),
              if (!_imagesUploaded)
                _ChecklistItem(
                  label: 'Upload your images',
                  checked: false,
                  onTap: _uploadImages,
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Content Router ──
  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return _ContactsList(onOpenChat: _openChat);
      default:
        return const SizedBox.shrink();
    }
  }

  void _openChat(String partnerUid) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(partnerUid: partnerUid)),
    );
  }
}

class _ContactsList extends StatefulWidget {
  final ValueChanged<String> onOpenChat;

  const _ContactsList({required this.onOpenChat});

  @override
  State<_ContactsList> createState() => _ContactsListState();
}

class _ContactsListState extends State<_ContactsList> {
  late final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = ConnectionService.myConnectionsStream();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final myUid = ConnectionService.myUid;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final docs = snap.data ?? const [];
          if (docs.isEmpty || myUid == null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedUserGroup,
                    color: c.textDim,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No matches yet — go say hi to someone!',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.textDim,
                    ),
                  ),
                ],
              ),
            );
          }
          final partnerUids = <String>[];
          for (final d in docs) {
            final users = ((d.data()['users'] as List?) ?? const [])
                .cast<String>();
            final partner = users.firstWhere(
              (u) => u != myUid,
              orElse: () => '',
            );
            if (partner.isNotEmpty) partnerUids.add(partner);
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final uid in partnerUids)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ContactTile(
                    uid: uid,
                    onTap: () => widget.onOpenChat(uid),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ContactTile extends StatefulWidget {
  final String uid;
  final VoidCallback onTap;

  const _ContactTile({required this.uid, required this.onTap});

  @override
  State<_ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends State<_ContactTile> {
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final name = (data['name'] as String?)?.trim().isNotEmpty == true
            ? data['name'] as String
            : 'User';
        final username = (data['username'] as String?) ?? '';
        final photo = (data['photoURL'] as String?) ?? '';
        return Material(
          color: c.card,
          borderRadius: BorderRadius.circular(34),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(34),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: c.cardBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: c.cardBorder,
                    backgroundImage: photo.isNotEmpty
                        ? NetworkImage(photo)
                        : null,
                    child: photo.isEmpty
                        ? HugeIcon(
                            icon: HugeIcons.strokeRoundedUser,
                            color: c.textDim,
                            size: 22,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        if (username.isNotEmpty)
                          Text(
                            '@$username',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: c.textDim,
                            ),
                          ),
                      ],
                    ),
                  ),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    color: c.textDim,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Section {
  final String title;
  final dynamic icon;
  const _Section(this.title, this.icon);
}

class _BackPanelButton extends StatelessWidget {
  final String label;
  final List<List<dynamic>> icon;
  final bool filled;
  final VoidCallback onTap;

  const _BackPanelButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = filled ? c.primary : Colors.white.withValues(alpha: 0.08);
    final fg = filled ? Colors.white : Colors.white;
    final border = filled
        ? Colors.transparent
        : Colors.white.withValues(alpha: 0.22);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(icon: icon, color: fg, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const _ChecklistItem({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: checked ? null : onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: checked ? c.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: checked
                          ? c.primary
                          : Colors.white.withValues(alpha: 0.4),
                      width: 1.6,
                    ),
                  ),
                  child: checked
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: checked
                          ? Colors.white.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.9),
                      decoration: checked ? TextDecoration.lineThrough : null,
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
