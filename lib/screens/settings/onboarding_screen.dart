import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/nexaryo_colors.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Page 1: Name & Username
  late final TextEditingController _nameController;
  final _usernameController = TextEditingController();
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameError;

  // Page 2: DOB & Gender
  DateTime? _dob;
  String? _gender;

  // Page 3: Permissions
  bool _locationGranted = false;
  bool _notificationsGranted = false;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController = TextEditingController(text: user?.displayName ?? '');
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _checkUsername() async {
    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() {
        _usernameError = 'Username cannot be empty';
        _isUsernameAvailable = null;
      });
      return;
    }

    if (username.length < 3) {
      setState(() {
        _usernameError = 'Username must be at least 3 characters';
        _isUsernameAvailable = null;
      });
      return;
    }

    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(username)) {
      setState(() {
        _usernameError = 'Only lowercase letters, numbers, . and _';
        _isUsernameAvailable = null;
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username)
          .get();

      setState(() {
        _isUsernameAvailable = !doc.exists;
        if (doc.exists) {
          _usernameError = 'Username is taken';
        }
      });
    } catch (e) {
      setState(() {
        _usernameError = 'Could not check username';
        _isUsernameAvailable = null;
      });
    } finally {
      setState(() => _isCheckingUsername = false);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _requestLocation() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      setState(() => _locationGranted = status.isGranted);
    } catch (e) {
      debugPrint('Location permission error: $e');
      // Try checking if already granted
      final status = await Permission.locationWhenInUse.status;
      setState(() => _locationGranted = status.isGranted);
    }
  }

  Future<void> _requestNotifications() async {
    try {
      final status = await Permission.notification.request();
      setState(() => _notificationsGranted = status.isGranted);
    } catch (e) {
      debugPrint('Notification permission error: $e');
      final status = await Permission.notification.status;
      setState(() => _notificationsGranted = status.isGranted);
    }
  }

  Future<void> _finish() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final name = _nameController.text.trim();
      final username = _usernameController.text.trim().toLowerCase();

      // Update display name if changed
      if (name.isNotEmpty && name != user.displayName) {
        await user.updateDisplayName(name);
      }

      final batch = FirebaseFirestore.instance.batch();

      // Reserve username
      if (username.isNotEmpty && _isUsernameAvailable == true) {
        batch.set(
          FirebaseFirestore.instance.collection('usernames').doc(username),
          {'uid': user.uid},
        );
      }

      // Update user doc
      batch.set(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
        {
          'name': name.isNotEmpty ? name : (user.displayName ?? ''),
          'nameLower': (name.isNotEmpty ? name : (user.displayName ?? ''))
              .toLowerCase(),
          'username': username.isNotEmpty ? username : null,
          'email': user.email ?? '',
          'photoURL': user.photoURL ?? '',
          'dob': _dob != null ? Timestamp.fromDate(_dob!) : null,
          'gender': _gender,
          'onboardingComplete': true,
          'lastLogin': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      // Cache onboarding complete locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);

      if (mounted) {
        widget.onComplete();
        return;
      }
    } catch (e) {
      debugPrint('Onboarding save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Something went wrong. Please try again.',
              style: GoogleFonts.montserrat(),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return Container(
                    width: i == _currentPage ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: i == _currentPage ? c.primary : c.cardBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildNamePage(c),
                  _buildDobGenderPage(c),
                  _buildPermissionsPage(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 1: Name & Username ──
  Widget _buildNamePage(NexaryoColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 20),
                Text(
                  "What's your name?",
                  style: TextStyle(
                    fontFamily: 'Miloner',
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can edit the name from your Google account',
                  style: GoogleFonts.montserrat(fontSize: 13, color: c.textDim),
                ),
                const SizedBox(height: 24),
                _buildTextField(c, _nameController, 'Display name'),
                const SizedBox(height: 20),
                Text(
                  'Choose a username',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lowercase letters, numbers, . and _ only',
                  style: GoogleFonts.montserrat(fontSize: 13, color: c.textDim),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        c,
                        _usernameController,
                        'username',
                      ),
                    ),
                    const SizedBox(width: 10),
                    _isCheckingUsername
                        ? SizedBox(
                            width: 52,
                            height: 52,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.primary,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: c.primary,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: IconButton(
                              icon: Text(
                                'Go',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              onPressed: _checkUsername,
                            ),
                          ),
                  ],
                ),
                if (_usernameError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _usernameError!,
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: c.accentWarm,
                    ),
                  ),
                ],
                if (_isUsernameAvailable == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Username is available!',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: c.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildNextButton(
            c,
            onTap: () {
              if (_nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Please enter your name',
                      style: GoogleFonts.montserrat(),
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
                return;
              }
              if (_isUsernameAvailable != true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Please check username availability',
                      style: GoogleFonts.montserrat(),
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
                return;
              }
              _nextPage();
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Page 2: DOB & Gender ──
  Widget _buildDobGenderPage(NexaryoColors c) {
    final genders = ['Male', 'Female', 'Other'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 20),
                Text(
                  'About you',
                  style: TextStyle(
                    fontFamily: 'Miloner',
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This helps us personalise your experience',
                  style: GoogleFonts.montserrat(fontSize: 13, color: c.textDim),
                ),
                const SizedBox(height: 32),
                Text(
                  'Date of Birth',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: c.card,
                  borderRadius: BorderRadius.circular(34),
                  child: InkWell(
                    onTap: _pickDob,
                    borderRadius: BorderRadius.circular(34),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(color: c.cardBorder),
                      ),
                      child: Text(
                        _dob != null
                            ? '${_dob!.day}/${_dob!.month}/${_dob!.year}'
                            : 'Tap to select',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: _dob != null ? c.textPrimary : c.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Gender',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: genders.map((g) {
                    final selected = _gender == g;
                    return Material(
                      color: selected ? c.primary : c.card,
                      borderRadius: BorderRadius.circular(34),
                      child: InkWell(
                        onTap: () => setState(() => _gender = g),
                        borderRadius: BorderRadius.circular(34),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            border: Border.all(
                              color: selected ? c.primary : c.cardBorder,
                            ),
                          ),
                          child: Text(
                            g,
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          _buildNextButton(
            c,
            onTap: () {
              if (_dob == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Please select your date of birth',
                      style: GoogleFonts.montserrat(),
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
                return;
              }
              if (_gender == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Please select your gender',
                      style: GoogleFonts.montserrat(),
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
                return;
              }
              _nextPage();
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Page 3: Permissions ──
  Widget _buildPermissionsPage(NexaryoColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 20),
                Text(
                  'Permissions',
                  style: TextStyle(
                    fontFamily: 'Miloner',
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We need a couple of permissions to get started',
                  style: GoogleFonts.montserrat(fontSize: 13, color: c.textDim),
                ),
                const SizedBox(height: 32),
                _buildPermissionTile(
                  c,
                  icon: HugeIcons.strokeRoundedLocation01,
                  title: 'Approximate Location',
                  subtitle: 'To show people near you',
                  granted: _locationGranted,
                  onTap: _requestLocation,
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  c,
                  icon: HugeIcons.strokeRoundedNotification01,
                  title: 'Notifications',
                  subtitle: 'To let you know when someone buzzes you',
                  granted: _notificationsGranted,
                  onTap: _requestNotifications,
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: c.primary,
              borderRadius: BorderRadius.circular(34),
              child: InkWell(
                onTap: _isSaving ? null : _finish,
                borderRadius: BorderRadius.circular(34),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: _isSaving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Finish',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPermissionTile(
    NexaryoColors c, {
    required List<List<dynamic>> icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
  }) {
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
                  color: granted ? c.primary.withOpacity(0.1) : c.cardBorder,
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
                      style: GoogleFonts.montserrat(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: c.textDim,
                      ),
                    ),
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

  Widget _buildTextField(
    NexaryoColors c,
    TextEditingController controller,
    String hint,
  ) {
    return TextField(
      controller: controller,
      style: GoogleFonts.montserrat(color: c.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.montserrat(color: c.textDim, fontSize: 14),
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

  Widget _buildNextButton(NexaryoColors c, {required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: c.primary,
        borderRadius: BorderRadius.circular(34),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(34),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'Next',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
