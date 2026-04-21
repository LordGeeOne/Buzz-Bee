import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../theme/nexaryo_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/section_header.dart';

class CardsSection extends StatelessWidget {
  const CardsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Cards',
            description:
                'Card component variations used for content containers.',
          ),

          // Basic Card
          _label(context, 'Basic Card'),
          const SizedBox(height: 12),
          _card(
            context,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Card Title', style: ts.heading3),
                  const SizedBox(height: 8),
                  Text(
                    'Basic card with the standard #1E1E1E background and #2A2A2A border.',
                    style: ts.bodySecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Card with Image Placeholder
          _label(context, 'Card with Header'),
          const SizedBox(height: 12),
          _card(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.15),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(33),
                    ),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedImage01,
                      size: 40,
                      color: c.primary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Card with Header', style: ts.bodyLarge),
                      const SizedBox(height: 6),
                      Text(
                        'Features a colored header area for imagery or accent content.',
                        style: ts.bodySecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // List-style Card
          _label(context, 'List Item Card'),
          const SizedBox(height: 12),
          ..._buildListCards(context),
          const SizedBox(height: 24),

          // Active/Selected Card
          _label(context, 'Active / Selected Card'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.primary.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(34),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedTick01,
                    color: c.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selected Item', style: ts.bodyLarge),
                      const SizedBox(height: 4),
                      Text(
                        'Primary accent tint for active states',
                        style: ts.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.cardBorder),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(33), child: child),
    );
  }

  List<Widget> _buildListCards(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final icons = [
      HugeIcons.strokeRoundedFile01,
      HugeIcons.strokeRoundedBookmark02,
      HugeIcons.strokeRoundedMail01,
    ];
    return List.generate(3, (i) {
      final titles = ['First Item', 'Second Item', 'Third Item'];
      final subtitles = [
        'Description for the first item',
        'Description for the second item',
        'Description for the third item',
      ];
      return Padding(
        padding: EdgeInsets.only(bottom: i < 2 ? 8 : 0),
        child: _card(
          context,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.cardBorder,
                    borderRadius: BorderRadius.circular(34),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: icons[i],
                      size: 20,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titles[i], style: ts.bodyLarge),
                      const SizedBox(height: 2),
                      Text(subtitles[i], style: ts.caption),
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
    });
  }
}
