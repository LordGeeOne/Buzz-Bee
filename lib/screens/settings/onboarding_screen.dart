import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/theme_provider.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/nexaryo_colors.dart';
import '../../widgets/profile_gallery_section.dart';
import '../people_screen.dart';

/// Multi-step onboarding flow.
///
/// Pages: identity → about → theme → interested-in → photo → gallery
/// → bio → permissions. Photo and gallery uploads commit immediately;
/// every other field is flushed in a single batched write on Finish.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _UsernameStatus { idle, checking, available, taken, invalid }

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _totalPages = 8;

  final _pageController = PageController();
  int _currentPage = 0;

  // Identity
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  Timer? _usernameDebounce;
  Timer? _nameDebounce;
  _UsernameStatus _usernameStatus = _UsernameStatus.idle;
  String? _usernameError;
  bool _userEditedUsername = false;

  // About
  DateTime? _dob;
  String? _gender;

  // Interested in
  String? _interestedIn;

  // Photo
  String? _photoUrl;
  bool _uploadingPhoto = false;
  final ImagePicker _picker = ImagePicker();

  // Bio
  static const List<String> _interestOptions = [
    'Music',
    'Movies',
    'Travel',
    'Coffee',
    'Cooking',
    'Hiking',
    'Gaming',
    'Books',
    'Fitness',
    'Photography',
    'Art',
    'Dancing',
    'Foodie',
    'Pets',
    'Tech',
    'Fashion',
    'Sports',
    'Yoga',
    'Nature',
    'Nightlife',
  ];
  static const List<_BioTemplate> _bioTemplates = [
    _BioTemplate(
      name: 'Casual',
      template: 'Just a chill soul into {interests}.',
    ),
    _BioTemplate(
      name: 'Adventurous',
      template: 'Always chasing the next adventure — {interests} included.',
    ),
    _BioTemplate(
      name: 'Romantic',
      template: 'A hopeless romantic with a soft spot for {interests}.',
    ),
    _BioTemplate(name: 'Witty', template: 'Fluent in sarcasm and {interests}.'),
    _BioTemplate(
      name: 'Minimalist',
      template: '{interests}. That\'s the pitch.',
    ),
  ];
  final Set<String> _selectedInterests = {};
  int _bioTemplateIndex = 0;

  // Permissions
  bool _locationGranted = false;
  bool _notificationsGranted = false;

  bool _isSaving = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController = TextEditingController(text: user?.displayName ?? '');
    _usernameController = TextEditingController();
    _nameController.addListener(_onNameChanged);
    _usernameController.addListener(_onUsernameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_nameController.text.trim().isNotEmpty) _suggestUsername();
    });
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameDebounce?.cancel();
    _pageController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Username auto-generation ─────────────────────────────────────────────

  void _onNameChanged() {
    if (_userEditedUsername) return;
    _nameDebounce?.cancel();
    _nameDebounce = Timer(const Duration(milliseconds: 400), _suggestUsername);
  }

  void _onUsernameChanged() {
    final auto = _slugifyName(_nameController.text);
    if (!_userEditedUsername &&
        _usernameController.text.isNotEmpty &&
        !_usernameController.text.startsWith(auto)) {
      _userEditedUsername = true;
    }
    _usernameDebounce?.cancel();
    _usernameDebounce = Timer(
      const Duration(milliseconds: 400),
      _validateUsername,
    );
  }

  String _slugifyName(String name) {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return slug.length > 12 ? slug.substring(0, 12) : slug;
  }

  String _randomDigits(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(10)).join();
  }

  Future<void> _suggestUsername() async {
    final base = _slugifyName(_nameController.text);
    if (base.length < 2) return;
    setState(() => _usernameStatus = _UsernameStatus.checking);
    String? candidate;
    for (var i = 0; i < 5; i++) {
      final guess = '$base${_randomDigits(3)}';
      if (!await _usernameTaken(guess)) {
        candidate = guess;
        break;
      }
    }
    if (!mounted) return;
    if (candidate != null) {
      _usernameController.removeListener(_onUsernameChanged);
      _usernameController.text = candidate;
      _usernameController.addListener(_onUsernameChanged);
      setState(() {
        _usernameStatus = _UsernameStatus.available;
        _usernameError = null;
      });
    } else {
      setState(() {
        _usernameStatus = _UsernameStatus.taken;
        _usernameError = 'Try editing the handle';
      });
    }
  }

  Future<bool> _usernameTaken(String username) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> _validateUsername() async {
    final u = _usernameController.text.trim().toLowerCase();
    if (u.isEmpty) {
      setState(() {
        _usernameStatus = _UsernameStatus.invalid;
        _usernameError = null;
      });
      return;
    }
    if (u.length < 3) {
      setState(() {
        _usernameStatus = _UsernameStatus.invalid;
        _usernameError = 'Min 3 characters';
      });
      return;
    }
    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(u)) {
      setState(() {
        _usernameStatus = _UsernameStatus.invalid;
        _usernameError = 'a–z, 0–9, . _ only';
      });
      return;
    }
    setState(() => _usernameStatus = _UsernameStatus.checking);
    final taken = await _usernameTaken(u);
    if (!mounted) return;
    setState(() {
      if (taken) {
        _usernameStatus = _UsernameStatus.taken;
        _usernameError = 'Taken';
      } else {
        _usernameStatus = _UsernameStatus.available;
        _usernameError = null;
      }
    });
  }

  // ── Pickers ──────────────────────────────────────────────────────────────

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final maxDob = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? maxDob,
      firstDate: DateTime(1900),
      lastDate: maxDob,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_uploadingPhoto) return;
    final source = await _chooseImageSource();
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1080,
        maxHeight: 1080,
      );
    } catch (_) {
      _toast("Couldn't open the picker");
      return;
    }
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final file = File(picked.path);
      final ext = _extensionOf(picked.path);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_randomDigits(4)}.$ext';
      final ref = FirebaseStorage.instance.ref('avatars/$_myUid/$fileName');
      await ref.putFile(
        file,
        SettableMetadata(contentType: _contentTypeFor(ext)),
      );
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(_myUid).set({
        'photoURL': url,
      }, SetOptions(merge: true));

      final old = _photoUrl;
      if (old != null && old.isNotEmpty && old != url) {
        try {
          final oldRef = FirebaseStorage.instance.refFromURL(old);
          if (oldRef.fullPath.startsWith('avatars/$_myUid/')) {
            await oldRef.delete();
          }
        } catch (_) {}
      }

      if (mounted) setState(() => _photoUrl = url);
    } catch (_) {
      _toast("Couldn't upload photo");
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<ImageSource?> _chooseImageSource() {
    final c = context.colors;
    final ts = context.textStyles;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('Add a photo', style: ts.heading3),
              const SizedBox(height: 16),
              _SheetOption(
                icon: HugeIcons.strokeRoundedCamera01,
                label: 'Camera',
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _SheetOption(
                icon: HugeIcons.strokeRoundedImage02,
                label: 'Gallery',
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final raw = path.substring(dot + 1).toLowerCase();
    final clean = raw.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return clean.isEmpty ? 'jpg' : clean;
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

  // ── Permissions ──────────────────────────────────────────────────────────

  Future<void> _requestLocation() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      setState(() => _locationGranted = status.isGranted);
    } catch (_) {
      final status = await Permission.locationWhenInUse.status;
      setState(() => _locationGranted = status.isGranted);
    }
  }

  Future<void> _requestNotifications() async {
    try {
      final status = await Permission.notification.request();
      setState(() => _notificationsGranted = status.isGranted);
    } catch (_) {
      final status = await Permission.notification.status;
      setState(() => _notificationsGranted = status.isGranted);
    }
  }

  // ── Bio helpers ──────────────────────────────────────────────────────────

  String _humanJoin(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }

  String _bioPreview(_BioTemplate t) {
    final list = _selectedInterests.toList();
    if (list.isEmpty) return t.template.replaceAll('{interests}', '…');
    return t.template.replaceAll('{interests}', _humanJoin(list));
  }

  // ── Finish ───────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final name = _nameController.text.trim();
      final username = _usernameController.text.trim().toLowerCase();
      final bio = _selectedInterests.isEmpty
          ? ''
          : _bioPreview(_bioTemplates[_bioTemplateIndex]);

      if (name.isNotEmpty && name != user.displayName) {
        await user.updateDisplayName(name);
      }

      final batch = FirebaseFirestore.instance.batch();

      if (username.isNotEmpty && _usernameStatus == _UsernameStatus.available) {
        batch.set(
          FirebaseFirestore.instance.collection('usernames').doc(username),
          {'uid': user.uid},
        );
      }

      batch.set(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
        {
          'name': name.isNotEmpty ? name : (user.displayName ?? ''),
          'nameLower': (name.isNotEmpty ? name : (user.displayName ?? ''))
              .toLowerCase(),
          'username': username.isNotEmpty ? username : null,
          'email': user.email ?? '',
          'photoURL': _photoUrl ?? user.photoURL ?? '',
          'dob': _dob != null ? Timestamp.fromDate(_dob!) : null,
          'gender': _gender,
          'interestedIn': _interestedIn,
          'bio': bio,
          'interests': _selectedInterests.toList(),
          'onboardingComplete': true,
          'lastLogin': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PeopleScreen()),
        );
      }
    } catch (e) {
      debugPrint('Onboarding save failed: $e');
      if (mounted) {
        _toast('Something went wrong. Try again?');
        setState(() => _isSaving = false);
      }
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

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              currentPage: _currentPage,
              totalPages: _totalPages,
              onBack: _currentPage > 0 ? _prevPage : null,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildIdentityPage(c),
                  _buildAboutPage(c),
                  _buildThemePage(c),
                  _buildInterestedInPage(c),
                  _buildPhotoPage(c),
                  _buildGalleryPage(c),
                  _buildBioPage(c),
                  _buildPermissionsPage(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 1: Identity ─────────────────────────────────────────────────────
  Widget _buildIdentityPage(NexaryoColors c) {
    final ts = context.textStyles;
    return _PageShell(
      title: 'Hey, what should we call you?',
      subtitle: "Your name and a handle that's all yours.",
      footer: _PrimaryButton(
        label: 'Next',
        onTap: () {
          if (_nameController.text.trim().isEmpty) {
            _toast('Add your name');
            return;
          }
          if (_usernameStatus != _UsernameStatus.available) {
            _toast('Pick an available handle');
            return;
          }
          _nextPage();
        },
      ),
      children: [
        const _FieldLabel('First name'),
        _RoundedTextField(
          controller: _nameController,
          hint: 'How friends know you',
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Username'),
        Row(
          children: [
            Expanded(
              child: _RoundedTextField(
                controller: _usernameController,
                hint: 'pick a vibey handle',
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Text('@', style: ts.label.copyWith(color: c.textDim)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _UsernameStatusIcon(status: _usernameStatus),
            IconButton(
              tooltip: 'Suggest another',
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedRefresh,
                color: c.textDim,
                size: 20,
              ),
              onPressed: () {
                _userEditedUsername = false;
                _suggestUsername();
              },
            ),
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _usernameError != null
              ? Padding(
                  key: ValueKey(_usernameError),
                  padding: const EdgeInsets.only(top: 6, left: 16),
                  child: Text(
                    _usernameError!,
                    style: ts.caption.copyWith(color: c.accentWarm),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('none')),
        ),
      ],
    );
  }

  // ── Page 2: About You ────────────────────────────────────────────────────
  Widget _buildAboutPage(NexaryoColors c) {
    final ts = context.textStyles;
    final genders = const ['Male', 'Female', 'Other'];
    return _PageShell(
      title: 'Tell us a bit about you',
      subtitle: 'The basics — we keep it short and sweet.',
      footer: _PrimaryButton(
        label: 'Next',
        onTap: () {
          if (_dob == null) {
            _toast('Pick your date of birth');
            return;
          }
          if (_gender == null) {
            _toast('Pick a gender');
            return;
          }
          _nextPage();
        },
      ),
      children: [
        const _FieldLabel('Date of birth'),
        Material(
          color: c.card,
          borderRadius: BorderRadius.circular(34),
          child: InkWell(
            onTap: _pickDob,
            borderRadius: BorderRadius.circular(34),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: c.cardBorder),
              ),
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCalendar03,
                    color: c.textDim,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _dob != null
                        ? '${_dob!.day}/${_dob!.month}/${_dob!.year}'
                        : 'Date of birth',
                    style: ts.body.copyWith(
                      color: _dob != null ? c.textPrimary : c.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Gender'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: genders.map((g) {
            return _SelectableChip(
              label: g,
              selected: _gender == g,
              onTap: () {
                setState(() => _gender = g);
                final themeId = switch (g) {
                  'Male' => 'lavender',
                  'Female' => 'passion',
                  _ => 'ember',
                };
                context.read<ThemeProvider>().setTheme(themeId);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Page 3: Theme ────────────────────────────────────────────────────────
  Widget _buildThemePage(NexaryoColors c) {
    final ts = context.textStyles;
    return _PageShell(
      title: 'Make it yours',
      subtitle: 'Pick a palette that matches your mood.',
      footer: _PrimaryButton(label: 'Next', onTap: _nextPage),
      children: [
        const _FieldLabel('Mode'),
        Consumer<ThemeProvider>(
          builder: (context, tp, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.cardBorder),
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: tp.isDark
                      ? HugeIcons.strokeRoundedSun01
                      : HugeIcons.strokeRoundedMoon,
                  color: c.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tp.isDark ? 'Light Mode' : 'Dark Mode',
                    style: ts.body,
                  ),
                ),
                Switch(
                  value: tp.isDark,
                  onChanged: tp.setDarkMode,
                  activeThumbColor: c.primary,
                  inactiveTrackColor: c.cardBorder,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Palette'),
        Consumer<ThemeProvider>(
          builder: (context, tp, _) => Column(
            children: NexaryoColors.palettes.map((p) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PaletteCard(
                  palette: p,
                  selected: tp.activeId == p.id,
                  isDark: tp.isDark,
                  onTap: () => tp.setTheme(p.id),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Page 4: Interested In ────────────────────────────────────────────────
  Widget _buildInterestedInPage(NexaryoColors c) {
    final options = const [
      ('Men', HugeIcons.strokeRoundedUser),
      ('Women', HugeIcons.strokeRoundedUser),
      ('Everyone', HugeIcons.strokeRoundedUserMultiple),
    ];
    return _PageShell(
      title: 'Who catches your eye?',
      subtitle: "We'll line up the right people for you.",
      footer: _PrimaryButton(
        label: 'Next',
        onTap: () {
          if (_interestedIn == null) {
            _toast('Pick one');
            return;
          }
          _nextPage();
        },
      ),
      children: [
        ...options.map((opt) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BigSelectTile(
              icon: opt.$2,
              label: opt.$1,
              selected: _interestedIn == opt.$1,
              onTap: () => setState(() => _interestedIn = opt.$1),
            ),
          );
        }),
      ],
    );
  }

  // ── Page 5: Profile photo ────────────────────────────────────────────────
  Widget _buildPhotoPage(NexaryoColors c) {
    return _PageShell(
      title: 'Show your best smile',
      subtitle: 'Your main photo is the first impression.',
      footer: _photoUrl == null
          ? _PrimaryButton(label: 'Add photo', onTap: _pickAndUploadPhoto)
          : _PrimaryButton(label: 'Next', onTap: _nextPage),
      children: [
        Center(
          child: GestureDetector(
            onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: _photoUrl != null ? c.primary : c.cardBorder,
                  width: _photoUrl != null ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_photoUrl != null)
                    Image.network(_photoUrl!, fit: BoxFit.cover)
                  else
                    Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedCamera01,
                        color: c.textDim,
                        size: 44,
                      ),
                    ),
                  if (_uploadingPhoto)
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
        ),
      ],
    );
  }

  // ── Page 6: Gallery ──────────────────────────────────────────────────────
  Widget _buildGalleryPage(NexaryoColors c) {
    final ts = context.textStyles;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_myUid)
          .snapshots(),
      builder: (context, snap) {
        final photos = ((snap.data?.data()?['gallery'] as List?) ?? const [])
            .whereType<String>()
            .toList();
        final remaining = 3 - photos.length;
        final canContinue = photos.length >= 3;
        return _PageShell(
          title: 'Add a few more',
          subtitle: canContinue
              ? "Looking great. Add more if you'd like."
              : 'Add at least 3 photos — show off your style.',
          footer: _PrimaryButton(
            label: canContinue ? 'Next' : '$remaining more to go',
            onTap: canContinue
                ? _nextPage
                : () => _toast(
                    'Add ${remaining == 1 ? '1 more photo' : '$remaining more photos'}',
                  ),
          ),
          children: [
            ProfileGallerySection(uid: _myUid, photos: photos, isSelf: true),
            const SizedBox(height: 12),
            Text(
              '3 minimum',
              style: ts.caption.copyWith(
                color: canContinue ? c.primary : c.textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Page 7: Bio ──────────────────────────────────────────────────────────
  Widget _buildBioPage(NexaryoColors c) {
    return _PageShell(
      title: 'What lights you up?',
      subtitle: 'Tap your interests, then pick a bio that sounds like you.',
      footer: _PrimaryButton(
        label: 'Next',
        onTap: () {
          if (_selectedInterests.isEmpty) {
            _toast('Pick an interest');
            return;
          }
          _nextPage();
        },
      ),
      children: [
        const _FieldLabel('Interests'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _interestOptions.map((opt) {
            final selected = _selectedInterests.contains(opt);
            return _SelectableChip(
              label: opt,
              selected: selected,
              onTap: () => setState(() {
                if (selected) {
                  _selectedInterests.remove(opt);
                } else {
                  _selectedInterests.add(opt);
                }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Vibe'),
        for (var i = 0; i < _bioTemplates.length; i++) ...[
          _BioTemplateCard(
            template: _bioTemplates[i],
            preview: _bioPreview(_bioTemplates[i]),
            selected: _bioTemplateIndex == i,
            onTap: () => setState(() => _bioTemplateIndex = i),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── Page 8: Permissions ──────────────────────────────────────────────────
  Widget _buildPermissionsPage(NexaryoColors c) {
    return _PageShell(
      title: 'Almost there!',
      subtitle: "Two quick taps and you're in.",
      footer: _PrimaryButton(
        label: "Let's buzz",
        loading: _isSaving,
        onTap: _finish,
      ),
      children: [
        _PermissionTile(
          icon: HugeIcons.strokeRoundedLocation01,
          title: 'Location',
          subtitle: 'Meet people near you',
          granted: _locationGranted,
          onTap: _requestLocation,
        ),
        const SizedBox(height: 12),
        _PermissionTile(
          icon: HugeIcons.strokeRoundedNotification01,
          title: 'Notifications',
          subtitle: "Don't miss a buzz",
          granted: _notificationsGranted,
          onTap: _requestNotifications,
        ),
      ],
    );
  }
}

// ── Top bar ────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final VoidCallback? onBack;

  const _TopBar({
    required this.currentPage,
    required this.totalPages,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: onBack != null
                ? IconButton(
                    padding: EdgeInsets.zero,
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowLeft01,
                      color: c.textDim,
                      size: 22,
                    ),
                    onPressed: onBack,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(totalPages, (i) {
                final active = i == currentPage;
                final passed = i < currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: active ? 32 : 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: active
                        ? c.primary
                        : (passed
                              ? c.primary.withValues(alpha: 0.45)
                              : c.cardBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

// ── Page shell ─────────────────────────────────────────────────────────────

class _PageShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget footer;
  const _PageShell({
    required this.title,
    this.subtitle,
    required this.children,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final ts = context.textStyles;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            title,
            style: ts.heading2.copyWith(
              fontFamily: 'Beli',
              fontSize: 40,
              height: 1.35,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: ts.bodySecondary),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: children,
            ),
          ),
          footer,
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Reusable widgets ───────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final ts = context.textStyles;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: ts.label.copyWith(
          color: c.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RoundedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Widget? prefix;
  const _RoundedTextField({
    required this.controller,
    required this.hint,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return TextField(
      controller: controller,
      style: ts.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: ts.body.copyWith(color: c.textDim),
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: c.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(34),
          borderSide: BorderSide(color: c.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(34),
          borderSide: BorderSide(color: c.primary),
        ),
      ),
    );
  }
}

class _UsernameStatusIcon extends StatelessWidget {
  final _UsernameStatus status;
  const _UsernameStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget child;
    switch (status) {
      case _UsernameStatus.checking:
        child = SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
        );
        break;
      case _UsernameStatus.available:
        child = HugeIcon(
          icon: HugeIcons.strokeRoundedTick01,
          color: c.primary,
          size: 22,
        );
        break;
      case _UsernameStatus.taken:
      case _UsernameStatus.invalid:
        child = HugeIcon(
          icon: HugeIcons.strokeRoundedCancel01,
          color: c.accentWarm,
          size: 22,
        );
        break;
      case _UsernameStatus.idle:
        child = const SizedBox.shrink();
        break;
    }
    return SizedBox(
      width: 28,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey(status),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return AnimatedScale(
      scale: selected ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 160),
      child: Material(
        color: selected ? c.primary : c.card,
        borderRadius: BorderRadius.circular(34),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(34),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: selected ? c.primary : c.cardBorder),
            ),
            child: Text(
              label,
              style: ts.button.copyWith(
                color: selected ? Colors.white : c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BigSelectTile extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BigSelectTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Material(
      color: selected ? c.primary.withValues(alpha: 0.15) : c.card,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected ? c.primary : c.cardBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? c.primary.withValues(alpha: 0.15)
                      : c.cardBorder,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: icon,
                    color: selected ? c.primary : c.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: ts.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? c.primary : c.textPrimary,
                  ),
                ),
              ),
              if (selected)
                HugeIcon(
                  icon: HugeIcons.strokeRoundedTick01,
                  color: c.primary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  final NexaryoPalette palette;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _PaletteCard({
    required this.palette,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final preview = isDark ? palette.dark : palette.light;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: selected ? c.primary : c.cardBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: [
                    Container(color: preview.background),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 24,
                      child: Container(color: preview.primary),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: 12,
                      height: 12,
                      child: Container(color: preview.accentWarm),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                palette.name,
                style: ts.bodyLarge.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (selected)
              HugeIcon(
                icon: HugeIcons.strokeRoundedTick01,
                color: c.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              HugeIcon(icon: icon, color: c.textPrimary, size: 22),
              const SizedBox(width: 14),
              Text(label, style: ts.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onTap;
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(34),
      child: InkWell(
        onTap: granted ? null : onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: granted ? c.primary : c.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: granted
                      ? c.primary.withValues(alpha: 0.1)
                      : c.cardBorder,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: icon,
                    color: granted ? c.primary : c.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ts.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: ts.caption),
                  ],
                ),
              ),
              if (granted)
                HugeIcon(
                  icon: HugeIcons.strokeRoundedTick01,
                  color: c.primary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: c.primary,
        borderRadius: BorderRadius.circular(34),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(34),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: ts.button.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BioTemplate {
  final String name;
  final String template;
  const _BioTemplate({required this.name, required this.template});
}

class _BioTemplateCard extends StatelessWidget {
  final _BioTemplate template;
  final String preview;
  final bool selected;
  final VoidCallback onTap;
  const _BioTemplateCard({
    required this.template,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Material(
      color: selected ? c.primary.withValues(alpha: 0.12) : c.card,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected ? c.primary.withValues(alpha: 0.5) : c.cardBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.name,
                      style: ts.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? c.primary : c.textPrimary,
                      ),
                    ),
                  ),
                  if (selected)
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedTick01,
                      color: c.primary,
                      size: 20,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(preview, style: ts.bodySecondary),
            ],
          ),
        ),
      ),
    );
  }
}
