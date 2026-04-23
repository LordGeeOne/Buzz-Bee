import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/app_text_styles.dart';
import '../theme/nexaryo_colors.dart';

/// Auto Bio screen.
///
/// User picks a few interests and a template. The template's `{interests}`
/// placeholder is filled in to produce a draft bio that can be returned
/// to the previous screen via `Navigator.pop(context, bio)`.
class AutoBioScreen extends StatefulWidget {
  /// Optional list of interests already saved for the user. Used to
  /// pre-select chips on first build.
  final List<String> initialInterests;

  const AutoBioScreen({super.key, this.initialInterests = const []});

  @override
  State<AutoBioScreen> createState() => _AutoBioScreenState();
}

class _AutoBioScreenState extends State<AutoBioScreen> {
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

  static const List<_BioTemplate> _templates = [
    _BioTemplate(
      name: 'Casual',
      template:
          "Just a chill soul into {interests}. Looking for genuine connections "
          "and someone to share the little moments with.",
    ),
    _BioTemplate(
      name: 'Adventurous',
      template:
          "Always chasing the next adventure — whether that's {interests} "
          "or somewhere new on the map. Come along for the ride?",
    ),
    _BioTemplate(
      name: 'Romantic',
      template:
          "A hopeless romantic with a soft spot for {interests}. Tell me your "
          "favourite story and I'll tell you mine.",
    ),
    _BioTemplate(
      name: 'Witty',
      template:
          "Fluent in sarcasm and {interests}. Swipe right if you can keep up "
          "with my playlist and my puns.",
    ),
    _BioTemplate(
      name: 'Minimalist',
      template: "{interests}. That's the whole pitch.",
    ),
  ];

  late final Set<String> _selected;
  late final TextEditingController _customController;
  int _templateIndex = 0;
  bool _saving = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialInterests};
    _customController = TextEditingController();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  List<String> get _allInterests {
    final extra = _customController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final combined = <String>{..._selected, ...extra}.toList();
    return combined;
  }

  String _previewFor(_BioTemplate template) {
    final interests = _allInterests;
    if (interests.isEmpty) {
      return template.template.replaceAll('{interests}', '…');
    }
    return template.template.replaceAll('{interests}', _humanJoin(interests));
  }

  String _humanJoin(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} '
        'and ${items.last}';
  }

  Future<void> _useBio() async {
    if (_saving) return;
    if (_allInterests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one interest')),
      );
      return;
    }
    final bio = _previewFor(_templates[_templateIndex]);
    if (_myUid.isNotEmpty) {
      setState(() => _saving = true);
      try {
        await FirebaseFirestore.instance.collection('users').doc(_myUid).set({
          'interests': _allInterests,
        }, SetOptions(merge: true));
      } catch (_) {
        // Non-fatal — still return the bio.
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    if (!mounted) return;
    Navigator.pop(context, bio);
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
            _AppBar(saving: _saving, onUse: _useBio),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text('Auto bio', style: ts.heading2),
                  const SizedBox(height: 6),
                  Text(
                    'Pick your interests, then choose a template. We will '
                    'fill it in for you.',
                    style: ts.bodySecondary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'INTERESTS',
                    style: ts.label.copyWith(
                      letterSpacing: 1.2,
                      color: c.textDim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InterestChips(
                    options: _interestOptions,
                    selected: _selected,
                    onToggle: (v) {
                      setState(() {
                        if (_selected.contains(v)) {
                          _selected.remove(v);
                        } else {
                          _selected.add(v);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _CustomInterestField(
                    controller: _customController,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'TEMPLATE',
                    style: ts.label.copyWith(
                      letterSpacing: 1.2,
                      color: c.textDim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _templates.length; i++) ...[
                    _TemplateCard(
                      template: _templates[i],
                      preview: _previewFor(_templates[i]),
                      selected: _templateIndex == i,
                      onTap: () => setState(() => _templateIndex = i),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
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

class _AppBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onUse;

  const _AppBar({required this.saving, required this.onUse});

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
          Expanded(child: Text('Auto bio', style: ts.heading3)),
          Material(
            color: c.primary,
            borderRadius: BorderRadius.circular(34),
            child: InkWell(
              onTap: saving ? null : onUse,
              borderRadius: BorderRadius.circular(34),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Use',
                        style: ts.button.copyWith(color: Colors.white),
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

class _InterestChips extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _InterestChips({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return Material(
          color: isSelected ? c.primary : c.card,
          borderRadius: BorderRadius.circular(34),
          child: InkWell(
            onTap: () => onToggle(opt),
            borderRadius: BorderRadius.circular(34),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                border: Border.all(
                  color: isSelected ? c.primary : c.cardBorder,
                ),
              ),
              child: Text(
                opt,
                style: ts.body.copyWith(
                  color: isSelected ? Colors.white : c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CustomInterestField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _CustomInterestField({
    required this.controller,
    required this.onChanged,
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
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedAdd01,
                color: c.textSecondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Add custom interests, comma separated',
                hintStyle: GoogleFonts.montserrat(
                  fontSize: 14,
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

class _TemplateCard extends StatelessWidget {
  final _BioTemplate template;
  final String preview;
  final bool selected;
  final VoidCallback onTap;

  const _TemplateCard({
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
                        color: selected ? c.primary : c.textPrimary,
                        fontWeight: FontWeight.w600,
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
