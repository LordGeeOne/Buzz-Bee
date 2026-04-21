import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/section_header.dart';
import '../../widgets/style_sample.dart';

class TypographySection extends StatelessWidget {
  const TypographySection({super.key});

  @override
  Widget build(BuildContext context) {
    final ts = context.textStyles;
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
