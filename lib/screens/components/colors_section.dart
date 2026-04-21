import 'package:flutter/material.dart';
import '../../theme/nexaryo_colors.dart';
import '../../widgets/section_header.dart';
import '../../widgets/color_swatch_card.dart';

class ColorsSection extends StatelessWidget {
  const ColorsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final usages = {
      'background': 'Scaffold & page backgrounds',
      'surface': 'Popups, dialogs, overlays',
      'card': 'Card containers, surfaces',
      'cardBorder': 'Borders, dividers',
      'primary': 'Accent, buttons, highlights',
      'accentWarm': 'Streaks, warnings, warmth',
      'textPrimary': 'Headings, main text',
      'textSecondary': 'Descriptions, subtitles',
      'textDim': 'Labels, hints, placeholders',
    };

    final entries = c.entries;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Colors',
            description:
                'The Nexaryo color palette. All apps share this dark theme.',
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final e = entries[index];
              return ColorSwatchCard(
                name: e.label,
                color: e.color,
                hexCode: e.color.hexCode,
                usage: usages[e.key] ?? '',
              );
            },
          ),
        ],
      ),
    );
  }
}
