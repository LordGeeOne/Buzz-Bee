import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/nexaryo_colors.dart';
import '../../widgets/section_header.dart';

class SpacingSection extends StatelessWidget {
  const SpacingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Spacing & Radii',
            description:
                'Standard spacing values and border radii used across components.',
          ),

          // Spacing
          _label(context, 'Spacing Scale'),
          const SizedBox(height: 12),
          ..._spacingRows(context),
          const SizedBox(height: 28),

          // Border Radius
          _label(context, 'Border Radius'),
          const SizedBox(height: 12),
          ..._radiusRows(context),
          const SizedBox(height: 28),

          // Padding reference
          _label(context, 'Common Padding Patterns'),
          const SizedBox(height: 12),
          _paddingExample(context, 'Page Padding', 'EdgeInsets.all(20)', 20),
          const SizedBox(height: 8),
          _paddingExample(context, 'Card Padding', 'EdgeInsets.all(16)', 16),
          const SizedBox(height: 8),
          _paddingExample(
            context,
            'Horizontal',
            'EdgeInsets.symmetric(h: 16)',
            16,
          ),
          const SizedBox(height: 8),
          _paddingExample(
            context,
            'Vertical (compact)',
            'EdgeInsets.symmetric(v: 12)',
            12,
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

  List<Widget> _spacingRows(BuildContext context) {
    final c = context.colors;
    final values = [4, 8, 12, 16, 20, 24, 32];
    return values.map((v) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '${v}px',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: v.toDouble() * 4,
              height: 24,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.primary.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _radiusRows(BuildContext context) {
    final c = context.colors;
    final values = [
      (8, 'Small — Chips, tags'),
      (12, 'Default — Cards, inputs, buttons'),
      (16, 'Large — Modals, sheets'),
      (18, 'XL — FABs, special containers'),
      (9999, 'Full — Circular avatars, pills'),
    ];
    return values.map((entry) {
      final (radius, desc) = entry;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(
                  radius.toDouble().clamp(0, 26),
                ),
                border: Border.all(color: c.primary, width: 1.5),
              ),
              child: Center(
                child: Text(
                  radius == 9999 ? '∞' : '$radius',
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                desc,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _paddingExample(
    BuildContext context,
    String name,
    String code,
    double value,
  ) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.cardBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
          ),
          Text(
            code,
            style: GoogleFonts.montserrat(fontSize: 12, color: c.textDim),
          ),
        ],
      ),
    );
  }
}
