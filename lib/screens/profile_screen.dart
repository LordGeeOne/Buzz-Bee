import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_text_styles.dart';
import '../theme/nexaryo_colors.dart';
import '../widgets/profile_gallery_section.dart';
import 'auto_bio_screen.dart';
import 'edit_profile_screen.dart';
import 'image_viewer_screen.dart';
import 'settings/settings_screen.dart';

/// Base profile screen used for viewing any user's profile.
///
/// If [uid] is null or matches the signed-in user, the screen renders
/// as the current user's own profile and exposes the Settings entry.
/// Otherwise it renders a peer profile view.
class ProfileScreen extends StatelessWidget {
  final String? uid;

  const ProfileScreen({super.key, this.uid});

  String? get _resolvedUid {
    final supplied = uid;
    if (supplied != null && supplied.isNotEmpty) {
      // Defensive guard: only allow Firebase-style uids so a bad caller
      // can't compose unexpected Firestore paths.
      if (RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(supplied)) {
        return supplied;
      }
      return null;
    }
    return FirebaseAuth.instance.currentUser?.uid;
  }

  bool get _isSelf {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final target = _resolvedUid;
    if (me == null || target == null) return false;
    return me == target;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final target = _resolvedUid;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppBar(isSelf: _isSelf),
            Expanded(
              child: target == null
                  ? Center(
                      child: Text('Not signed in', style: ts.bodySecondary),
                    )
                  : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(target)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return Center(
                            child: CircularProgressIndicator(color: c.primary),
                          );
                        }
                        final data =
                            snap.data?.data() ?? const <String, dynamic>{};
                        return _ProfileBody(
                          uid: target,
                          data: data,
                          isSelf: _isSelf,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  final bool isSelf;

  const _AppBar({required this.isSelf});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSelf ? 'Your profile' : 'Profile',
              style: ts.heading3,
            ),
          ),
          if (isSelf) ...[
            Container(
              height: 68,
              width: 68,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(34),
              ),
              child: IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedEdit02,
                  color: c.textDim,
                  size: 24,
                ),
                iconSize: 24,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 68,
              width: 68,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(34),
              ),
              child: IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedSettings01,
                  color: c.textDim,
                  size: 24,
                ),
                iconSize: 24,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final bool isSelf;

  const _ProfileBody({
    required this.uid,
    required this.data,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;

    final name = (data['name'] as String?)?.trim().isNotEmpty == true
        ? data['name'] as String
        : 'Unknown';
    final username = (data['username'] as String?) ?? '';
    final photo = (data['photoURL'] as String?) ?? '';
    final gender = (data['gender'] as String?) ?? '';
    final interestedIn = (data['interestedIn'] as String?) ?? '';
    final bio = (data['bio'] as String?) ?? '';
    final interests = ((data['interests'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final gallery = ((data['gallery'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final ratingRaw = data['rating'];
    final int rating = ratingRaw is num ? ratingRaw.round().clamp(0, 5) : 0;
    final dobTs = data['dob'];
    DateTime? dob;
    if (dobTs is Timestamp) dob = dobTs.toDate();
    final age = dob != null ? _calcAge(dob) : null;

    final ageGenderParts = <String>[
      if (age != null) '$age',
      if (gender.isNotEmpty) gender,
    ];
    final ageGenderLine = ageGenderParts.join(', ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Avatar (left, square) + identity. Photo size is capped so a
        // large source image can't push the row past the screen width.
        LayoutBuilder(
          builder: (context, constraints) {
            final photoSide = (constraints.maxWidth * 0.4).clamp(120.0, 180.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: photoSide,
                  height: photoSide,
                  child: _ProfilePhoto(
                    photoUrl: photo,
                    isSelf: isSelf,
                    heroTag: 'profile-photo-$uid',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: ts.heading2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('@$username', style: ts.caption),
                      ],
                      if (ageGenderLine.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(ageGenderLine, style: ts.bodySecondary),
                      ],
                      const SizedBox(height: 4),
                      _InterestedInLine(
                        value: interestedIn,
                        isSelf: isSelf,
                        onEdit: () => _editInterestedIn(context, interestedIn),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 20),

        // Action buttons (peers only).
        if (!isSelf) ...[
          Row(
            children: [
              Expanded(
                child: _ProfileActionButton(
                  label: 'Message',
                  icon: HugeIcons.strokeRoundedMessage01,
                  filled: true,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Messaging coming soon')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileActionButton(
                  label: 'Connect',
                  icon: HugeIcons.strokeRoundedUserAdd01,
                  filled: false,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Connect coming soon')),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        // Bio section
        _BioSection(bio: bio, isSelf: isSelf, initialInterests: interests),

        const SizedBox(height: 16),

        // Rating row (matches dashboard treatment)
        _RatingCard(rating: rating),

        const SizedBox(height: 24),

        // Gallery section (up to 9 photos)
        ProfileGallerySection(uid: uid, photos: gallery, isSelf: isSelf),
      ],
    );
  }

  static int _calcAge(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    final hadBirthday =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age -= 1;
    return age < 0 ? 0 : age;
  }

  Future<void> _editInterestedIn(BuildContext context, String current) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (ctx) => _InterestedInPicker(current: current),
    );
    if (selected == null) return;
    final value = selected.isEmpty ? null : selected;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'interestedIn': value,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('interestedIn update failed: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update your preference")),
      );
    }
  }
}

class _RatingCard extends StatelessWidget {
  final int rating;
  const _RatingCard({required this.rating});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.cardBorder),
      ),
      child: Row(
        children: [
          Text('Rating', style: ts.bodySecondary),
          const SizedBox(width: 12),
          ...List.generate(5, (i) {
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedStar,
                color: i < rating
                    ? c.accentWarm
                    : c.textDim.withValues(alpha: 0.4),
                size: 18,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final String label;
  final List<List<dynamic>> icon;
  final bool filled;
  final VoidCallback onTap;

  const _ProfileActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Material(
      color: filled ? c.primary : c.card,
      borderRadius: BorderRadius.circular(34),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: filled ? Colors.transparent : c.cardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(
                icon: icon,
                color: filled ? Colors.white : c.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: ts.button.copyWith(
                  color: filled ? Colors.white : c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BioSection extends StatefulWidget {
  final String bio;
  final bool isSelf;
  final List<String> initialInterests;

  const _BioSection({
    required this.bio,
    required this.isSelf,
    required this.initialInterests,
  });

  @override
  State<_BioSection> createState() => _BioSectionState();
}

class _BioSectionState extends State<_BioSection> {
  static const int _maxWords = 200;

  late final TextEditingController _controller;
  bool _editing = false;
  bool _saving = false;
  String _saved = '';

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _saved = widget.bio;
    _controller = TextEditingController(text: widget.bio);
  }

  @override
  void didUpdateWidget(covariant _BioSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync external updates only when not actively editing.
    if (!_editing && widget.bio != _saved) {
      _saved = widget.bio;
      _controller.text = widget.bio;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _wordCount(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  String _capWords(String s, int max) {
    final words = s.trim().split(RegExp(r'\s+'));
    if (words.length <= max) return s;
    return words.take(max).join(' ');
  }

  Future<void> _save() async {
    if (_saving) return;
    var text = _controller.text.trim();
    if (_wordCount(text) > _maxWords) {
      text = _capWords(text, _maxWords);
      _controller.text = text;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(_myUid).set({
        'bio': text,
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _saved = text;
        _editing = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Bio save failed: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't save your bio")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    setState(() {
      _controller.text = _saved;
      _editing = false;
    });
  }

  Future<void> _openAutoBio() async {
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AutoBioScreen(initialInterests: widget.initialInterests),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _controller.text = _capWords(result, _maxWords);
      _editing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final words = _wordCount(_controller.text);
    final overLimit = words > _maxWords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isSelf && !_editing && _saved.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: _SmallTextButton(
              label: 'Edit',
              icon: HugeIcons.strokeRoundedEdit02,
              onTap: () => setState(() => _editing = true),
            ),
          ),
        widget.isSelf
            ? _buildSelfBody(c, ts, words, overLimit)
            : _buildPeerBody(c, ts),
      ],
    );
  }

  Widget _buildPeerBody(NexaryoColors c, AppTextStyles ts) {
    if (_saved.isEmpty) {
      return Text(
        "This user hasn't written a bio yet.",
        style: ts.bodySecondary,
      );
    }
    return Text(_saved, style: ts.bodyLarge);
  }

  Widget _buildSelfBody(
    NexaryoColors c,
    AppTextStyles ts,
    int words,
    bool overLimit,
  ) {
    final showEditor = _editing || _saved.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!showEditor)
          Text(_saved, style: ts.bodyLarge)
        else ...[
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 4,
            onChanged: (_) => setState(() {}),
            style: ts.bodyLarge,
            decoration: InputDecoration(
              hintText:
                  'Tell people what makes you, you. Up to '
                  '$_maxWords words.',
              hintStyle: ts.bodySecondary,
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$words / $_maxWords words',
                style: ts.caption.copyWith(
                  color: overLimit ? c.accentWarm : c.textDim,
                ),
              ),
              const Spacer(),
              if (_editing && _saved.isNotEmpty)
                _SmallTextButton(
                  label: 'Cancel',
                  onTap: _saving ? null : _cancel,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BioActionButton(
                  label: 'Auto bio',
                  icon: HugeIcons.strokeRoundedAiMagic,
                  filled: false,
                  onTap: _saving ? null : _openAutoBio,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BioActionButton(
                  label: 'Save bio',
                  icon: HugeIcons.strokeRoundedTick01,
                  filled: true,
                  loading: _saving,
                  onTap: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SmallTextButton extends StatelessWidget {
  final String label;
  final List<List<dynamic>>? icon;
  final VoidCallback? onTap;

  const _SmallTextButton({required this.label, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              HugeIcon(icon: icon!, color: c.primary, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: ts.caption.copyWith(
                color: onTap == null ? c.textDim : c.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BioActionButton extends StatelessWidget {
  final String label;
  final List<List<dynamic>> icon;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  const _BioActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final disabled = onTap == null;
    return Material(
      color: filled ? (disabled ? c.cardBorder : c.primary) : c.card,
      borderRadius: BorderRadius.circular(34),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: filled ? Colors.transparent : c.cardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else
                HugeIcon(
                  icon: icon,
                  color: filled ? Colors.white : c.textPrimary,
                  size: 18,
                ),
              const SizedBox(width: 8),
              Text(
                label,
                style: ts.button.copyWith(
                  color: filled ? Colors.white : c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePhoto extends StatefulWidget {
  final String photoUrl;
  final bool isSelf;
  final String heroTag;

  static const double _radius = 24;

  const _ProfilePhoto({
    required this.photoUrl,
    required this.isSelf,
    required this.heroTag,
  });

  @override
  State<_ProfilePhoto> createState() => _ProfilePhotoState();
}

class _ProfilePhotoState extends State<_ProfilePhoto> {
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _open(BuildContext context) {
    if (_uploading) return;
    if (widget.isSelf) {
      _showSelfOptions(context);
    } else {
      _viewImage(context);
    }
  }

  void _viewImage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          imageUrl: widget.photoUrl,
          heroTag: widget.heroTag,
        ),
      ),
    );
  }

  Future<void> _changePhoto(BuildContext context) async {
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1080,
        maxHeight: 1080,
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Profile photo pick failed: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open the picker")));
      return;
    }
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final file = File(picked.path);
      final ext = _extensionOf(picked.path);
      final contentType = _contentTypeFor(ext);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_'
          '${_random4()}.$ext';
      final ref = FirebaseStorage.instance.ref('avatars/$_myUid/$fileName');
      await ref.putFile(file, SettableMetadata(contentType: contentType));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(_myUid).set({
        'photoURL': url,
      }, SetOptions(merge: true));
      // Best-effort: delete the previous avatar from Storage if it lives
      // in our avatars/ bucket path.
      final old = widget.photoUrl;
      if (old.isNotEmpty && old != url) {
        try {
          final oldRef = FirebaseStorage.instance.refFromURL(old);
          if (oldRef.fullPath.startsWith('avatars/$_myUid/')) {
            await oldRef.delete();
          }
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Profile photo upload failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update your photo")),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final raw = path.substring(dot + 1).toLowerCase();
    // Strip query strings or odd characters.
    final clean = raw.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.isEmpty) return 'jpg';
    return clean;
  }

  String _contentTypeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  String _random4() {
    final r = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<ImageSource?> _chooseSource(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('Change profile photo', style: ts.heading3),
              const SizedBox(height: 16),
              _OptionTile(
                icon: HugeIcons.strokeRoundedCamera01,
                label: 'Take a photo',
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 10),
              _OptionTile(
                icon: HugeIcons.strokeRoundedImage02,
                label: 'Choose from gallery',
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSelfOptions(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Profile photo', style: ts.heading3),
                const SizedBox(height: 16),
                if (widget.photoUrl.isNotEmpty) ...[
                  _OptionTile(
                    icon: HugeIcons.strokeRoundedView,
                    label: 'View',
                    onTap: () {
                      Navigator.pop(ctx);
                      _viewImage(context);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                _OptionTile(
                  icon: HugeIcons.strokeRoundedImageUpload,
                  label: 'Change',
                  onTap: () {
                    Navigator.pop(ctx);
                    _changePhoto(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(_ProfilePhoto._radius),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(_ProfilePhoto._radius),
        child: Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(_ProfilePhoto._radius),
            border: Border.all(color: c.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: widget.heroTag,
                child: widget.photoUrl.isNotEmpty
                    ? Image.network(
                        widget.photoUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: c.card,
                            child: Center(
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: c.primary,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) =>
                            _placeholder(context),
                      )
                    : _placeholder(context),
              ),
              if (_uploading)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const Center(
                    child: SizedBox(
                      height: 28,
                      width: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final c = context.colors;
    return Center(
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedUser,
        color: c.textDim,
        size: 40,
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(34),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: c.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.cardBorder,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: HugeIcon(icon: icon, color: c.textSecondary, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: ts.bodyLarge)),
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
  }
}

class _InterestedInLine extends StatelessWidget {
  final String value;
  final bool isSelf;
  final VoidCallback onEdit;

  const _InterestedInLine({
    required this.value,
    required this.isSelf,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final hasValue = value.isNotEmpty;

    if (!isSelf && !hasValue) return const SizedBox.shrink();

    final label = hasValue
        ? 'Interested in: $value'
        : 'Interested in: tap to set';
    final textWidget = Text(
      label,
      style: ts.bodySecondary.copyWith(
        color: hasValue ? c.textSecondary : c.primary,
        decoration: isSelf ? TextDecoration.underline : null,
        decorationColor: c.primary.withValues(alpha: 0.5),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (!isSelf) return textWidget;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: textWidget),
            const SizedBox(width: 4),
            HugeIcon(
              icon: HugeIcons.strokeRoundedEdit02,
              color: c.textDim,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _InterestedInPicker extends StatelessWidget {
  final String current;

  const _InterestedInPicker({required this.current});

  static const _options = ['Male', 'Female', 'Other', 'Everyone'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Interested in', style: ts.heading3),
            const SizedBox(height: 6),
            Text(
              'Who would you like to be matched with?',
              style: ts.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            for (final option in _options) ...[
              _PickerOption(
                label: option,
                selected: option == current,
                onTap: () => Navigator.pop(context, option),
              ),
              const SizedBox(height: 10),
            ],
            if (current.isNotEmpty)
              _PickerOption(
                label: 'Clear',
                selected: false,
                destructive: true,
                onTap: () => Navigator.pop(context, ''),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  final String label;
  final bool selected;
  final bool destructive;
  final VoidCallback onTap;

  const _PickerOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final fg = destructive
        ? c.accentWarm
        : (selected ? c.primary : c.textPrimary);
    final bg = selected ? c.primary.withValues(alpha: 0.15) : c.surface;
    final border = selected ? c.primary.withValues(alpha: 0.4) : c.cardBorder;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(34),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: ts.bodyLarge.copyWith(color: fg)),
              ),
              if (selected)
                HugeIcon(
                  icon: HugeIcons.strokeRoundedTick01,
                  color: c.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
