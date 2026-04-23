import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/app_text_styles.dart';
import '../theme/nexaryo_colors.dart';

/// Edit profile screen. Allows updating identity fields that must
/// match the user's National ID. Limited to two changes per 90 days.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const int _changeLimit = 2;
  static const int _windowDays = 90;

  final _firstNameController = TextEditingController();
  final _surnameController = TextEditingController();

  String? _gender;
  DateTime? _dob;

  // Original values for change detection.
  String _origFirstName = '';
  String _origSurname = '';
  String? _origGender;
  DateTime? _origDob;

  List<DateTime> _editHistory = const [];
  bool _loading = true;
  bool _saving = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_myUid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_myUid)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};

      final fullName = (data['name'] as String?)?.trim() ?? '';
      String firstName = (data['firstName'] as String?)?.trim() ?? '';
      String surname = (data['surname'] as String?)?.trim() ?? '';
      if (firstName.isEmpty && surname.isEmpty && fullName.isNotEmpty) {
        final parts = fullName.split(RegExp(r'\s+'));
        firstName = parts.first;
        surname = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }

      _origFirstName = firstName;
      _origSurname = surname;
      _firstNameController.text = firstName;
      _surnameController.text = surname;

      _origGender = (data['gender'] as String?)?.trim().isNotEmpty == true
          ? data['gender'] as String
          : null;
      _gender = _origGender;

      final dobTs = data['dob'];
      if (dobTs is Timestamp) {
        _origDob = dobTs.toDate();
        _dob = _origDob;
      }

      final history = (data['identityEditHistory'] as List?) ?? const [];
      _editHistory = history
          .whereType<Timestamp>()
          .map((t) => t.toDate())
          .toList();
    } catch (_) {
      // ignore — UI will show empty fields
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DateTime> get _recentEdits {
    final cutoff = DateTime.now().subtract(const Duration(days: _windowDays));
    return _editHistory.where((d) => d.isAfter(cutoff)).toList();
  }

  int get _editsRemaining =>
      (_changeLimit - _recentEdits.length).clamp(0, _changeLimit);

  DateTime? get _nextAvailableDate {
    final recent = _recentEdits;
    if (recent.length < _changeLimit) return null;
    recent.sort();
    return recent.first.add(const Duration(days: _windowDays));
  }

  bool get _hasChanges {
    final fn = _firstNameController.text.trim();
    final sn = _surnameController.text.trim();
    return fn != _origFirstName ||
        sn != _origSurname ||
        _gender != _origGender ||
        !_sameDate(_dob, _origDob);
  }

  bool _sameDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
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

  Future<void> _save() async {
    if (_saving) return;
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }
    if (_editsRemaining <= 0) {
      _toast(
        'You have reached the limit of $_changeLimit changes per '
        '$_windowDays days',
      );
      return;
    }

    final firstName = _firstNameController.text.trim();
    final surname = _surnameController.text.trim();
    if (firstName.isEmpty) {
      _toast('First name is required');
      return;
    }
    if (_gender == null) {
      _toast('Please select a gender');
      return;
    }
    if (_dob == null) {
      _toast('Please select your date of birth');
      return;
    }

    final confirmed = await _confirmChange();
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final fullName = surname.isEmpty ? firstName : '$firstName $surname';
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && fullName != user.displayName) {
        await user.updateDisplayName(fullName);
      }

      await FirebaseFirestore.instance.collection('users').doc(_myUid).set({
        'firstName': firstName,
        'surname': surname,
        'name': fullName,
        'nameLower': fullName.toLowerCase(),
        'gender': _gender,
        'dob': Timestamp.fromDate(_dob!),
        'identityEditHistory': FieldValue.arrayUnion([Timestamp.now()]),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _toast('Profile updated');
      Navigator.pop(context);
    } catch (_) {
      _toast('Could not save changes');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmChange() {
    final c = context.colors;
    final ts = context.textStyles;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('Confirm change', style: ts.heading3),
        content: Text(
          'These details must match your National ID. You will have '
          '${_editsRemaining - 1} change(s) left in the next $_windowDays days. '
          'Continue?',
          style: ts.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: ts.button.copyWith(color: c.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save', style: ts.button.copyWith(color: c.primary)),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppBar(saving: _saving, hasChanges: _hasChanges, onSave: _save),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.primary))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      children: [
                        _IdentityNotice(
                          editsRemaining: _editsRemaining,
                          changeLimit: _changeLimit,
                          windowDays: _windowDays,
                          nextAvailable: _nextAvailableDate,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'NAME',
                          style: ts.label.copyWith(
                            letterSpacing: 1.2,
                            color: c.textDim,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _LabeledField(
                          label: 'First name',
                          controller: _firstNameController,
                          icon: HugeIcons.strokeRoundedUser,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 12),
                        _LabeledField(
                          label: 'Surname',
                          controller: _surnameController,
                          icon: HugeIcons.strokeRoundedUserGroup,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'BIRTHDAY',
                          style: ts.label.copyWith(
                            letterSpacing: 1.2,
                            color: c.textDim,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DateField(value: _dob, onTap: _pickDob),
                        const SizedBox(height: 24),
                        Text(
                          'GENDER',
                          style: ts.label.copyWith(
                            letterSpacing: 1.2,
                            color: c.textDim,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _GenderSelector(
                          value: _gender,
                          onChanged: (g) => setState(() => _gender = g),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  final bool saving;
  final bool hasChanges;
  final VoidCallback onSave;

  const _AppBar({
    required this.saving,
    required this.hasChanges,
    required this.onSave,
  });

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
              onPressed: saving ? null : () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('Edit profile', style: ts.heading3)),
          Material(
            color: hasChanges ? c.primary : c.card,
            borderRadius: BorderRadius.circular(34),
            child: InkWell(
              onTap: saving || !hasChanges ? null : onSave,
              borderRadius: BorderRadius.circular(34),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                    color: hasChanges ? Colors.transparent : c.cardBorder,
                  ),
                ),
                child: saving
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Save',
                        style: ts.button.copyWith(
                          color: hasChanges ? Colors.white : c.textDim,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _IdentityNotice extends StatelessWidget {
  final int editsRemaining;
  final int changeLimit;
  final int windowDays;
  final DateTime? nextAvailable;

  const _IdentityNotice({
    required this.editsRemaining,
    required this.changeLimit,
    required this.windowDays,
    required this.nextAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final exhausted = editsRemaining <= 0;
    final accent = exhausted ? c.accentWarm : c.primary;

    String secondary;
    if (exhausted && nextAvailable != null) {
      secondary =
          'You can change these details again on ${_format(nextAvailable!)}.';
    } else {
      secondary =
          '$editsRemaining of $changeLimit changes left in the next '
          '$windowDays days.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedIdentityCard,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Must match your National ID',
                  style: ts.bodyLarge.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Name, surname, gender and date of birth must reflect '
                  'your National ID. Limit: $changeLimit changes per '
                  '$windowDays days.',
                  style: ts.bodySecondary,
                ),
                const SizedBox(height: 6),
                Text(secondary, style: ts.caption.copyWith(color: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _format(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final List<List<dynamic>> icon;
  final TextCapitalization textCapitalization;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.icon,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: c.card,
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
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: textCapitalization,
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: label,
                hintStyle: GoogleFonts.montserrat(
                  fontSize: 15,
                  color: c.textDim,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final DateTime? value;
  final VoidCallback onTap;

  const _DateField({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final formatted = value != null
        ? '${value!.day.toString().padLeft(2, '0')} / '
              '${value!.month.toString().padLeft(2, '0')} / '
              '${value!.year}'
        : 'Tap to select';
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(34),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedBirthdayCake,
                    color: c.textSecondary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  formatted,
                  style: ts.bodyLarge.copyWith(
                    color: value != null ? c.textPrimary : c.textDim,
                  ),
                ),
              ),
              HugeIcon(
                icon: HugeIcons.strokeRoundedCalendar01,
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

class _GenderSelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;

  static const _options = ['Male', 'Female', 'Other'];

  const _GenderSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _options.map((g) {
        final selected = value == g;
        return Material(
          color: selected ? c.primary : c.card,
          borderRadius: BorderRadius.circular(34),
          child: InkWell(
            onTap: () => onChanged(g),
            borderRadius: BorderRadius.circular(34),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: selected ? c.primary : c.cardBorder),
              ),
              child: Text(
                g,
                style: ts.button.copyWith(
                  color: selected ? Colors.white : c.textPrimary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
