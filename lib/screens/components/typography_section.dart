import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/nexaryo_colors.dart';
import '../../widgets/section_header.dart';
import '../../widgets/style_sample.dart';

/// All custom font families bundled in `assets/fonts/` and registered in
/// `pubspec.yaml`. Update both places when adding or removing fonts.
const List<String> kCustomFontFamilies = [
  'Beli',
  'Cafigine',
  'Elistora',
  'Klomisk',
  'Miloner',
  'Mirella',
  'Pastone',
  'Petrichor',
  'Veneza',
];

class TypographySection extends StatelessWidget {
  const TypographySection({super.key});

  @override
  Widget build(BuildContext context) {
    final ts = context.textStyles;
    final c = context.colors;
    final styles = [
      _StyleEntry('Heading 1', ts.heading1, 'Page Titles'),
      _StyleEntry('Heading 2', ts.heading2, 'Section Titles'),
      _StyleEntry('Heading 3', ts.heading3, 'Subsection Titles'),
      _StyleEntry('Body Large', ts.bodyLarge, 'Emphasized Body Text'),
      _StyleEntry('Body', ts.body, 'Default Body Text'),
      _StyleEntry('Body Secondary', ts.bodySecondary, 'Secondary Body Text'),
      _StyleEntry('Label', ts.label, 'Form Labels & Tags'),
      _StyleEntry('Caption', ts.caption, 'Hints & Timestamps'),
      _StyleEntry('Button', ts.button, 'Button Labels'),
      _StyleEntry('App Bar Title', ts.appBarTitle, 'App Bar Title Text'),
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Typography',
            description:
                'Montserrat is the standard font across all Nexaryo apps.',
          ),
          ...styles.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StyleSample(
                name: s.name,
                style: s.style,
                sampleText: s.sample,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Custom Fonts',
            description: 'Display fonts bundled with the app.',
          ),
          ...kCustomFontFamilies.map(
            (family) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FontSample(family: family, color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleEntry {
  final String name;
  final TextStyle style;
  final String sample;
  _StyleEntry(this.name, this.style, this.sample);
}

class _FontSample extends StatelessWidget {
  const _FontSample({required this.family, required this.color});

  final String family;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(family, style: TextStyle(fontSize: 12, color: c.textDim)),
          const SizedBox(height: 6),
          Text(
            'NEXARYO',
            style: TextStyle(fontFamily: family, fontSize: 28, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            'Buzz Bee',
            style: TextStyle(
              fontFamily: family,
              fontSize: 22,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
