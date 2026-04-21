import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../theme/nexaryo_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/section_header.dart';

class ButtonsSection extends StatelessWidget {
  const ButtonsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Buttons',
            description: 'Button variants and states used across Nexaryo apps.',
          ),

          // Primary Filled
          _subsection(context, 'Primary Filled'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _primaryButton(context, 'Enabled', enabled: true),
              _primaryButton(context, 'Disabled', enabled: false),
            ],
          ),
          const SizedBox(height: 28),

          // Outlined
          _subsection(context, 'Outlined'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _outlinedButton(context, 'Enabled', enabled: true),
              _outlinedButton(context, 'Disabled', enabled: false),
            ],
          ),
          const SizedBox(height: 28),

          // Text Buttons
          _subsection(context, 'Text Buttons'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              TextButton(
                onPressed: () {},
                child: Text(
                  'Text Button',
                  style: GoogleFonts.montserrat(
                    color: c.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: null,
                child: Text(
                  'Disabled',
                  style: GoogleFonts.montserrat(
                    color: c.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Icon Buttons
          _subsection(context, 'Icon Buttons'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _iconButton(context, HugeIcons.strokeRoundedPlay, enabled: true),
              _iconButton(context, HugeIcons.strokeRoundedPause, enabled: true),
              _iconButton(context, HugeIcons.strokeRoundedNext, enabled: true),
              _iconButton(
                context,
                HugeIcons.strokeRoundedSettings01,
                enabled: false,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // FABs
          _subsection(context, 'Floating Action Buttons'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FloatingActionButton.small(
                heroTag: 'fab_small',
                onPressed: () {},
                backgroundColor: c.primary,
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedAdd01,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              FloatingActionButton(
                heroTag: 'fab_default',
                onPressed: () {},
                backgroundColor: c.primary,
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedAdd01,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              FloatingActionButton.extended(
                heroTag: 'fab_extended',
                onPressed: () {},
                backgroundColor: c.primary,
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedAdd01,
                  color: Colors.white,
                  size: 24,
                ),
                label: Text('Create', style: context.textStyles.button),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _subsection(BuildContext context, String title) {
    return Text(
      title,
      style: GoogleFonts.montserrat(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
      ),
    );
  }

  Widget _primaryButton(
    BuildContext context,
    String label, {
    required bool enabled,
  }) {
    final c = context.colors;
    return ElevatedButton(
      onPressed: enabled ? () {} : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: c.primary,
        disabledBackgroundColor: c.primary.withValues(alpha: 0.3),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
        minimumSize: const Size(0, 68),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
      ),
      child: Text(
        label,
        style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _outlinedButton(
    BuildContext context,
    String label, {
    required bool enabled,
  }) {
    final c = context.colors;
    return OutlinedButton(
      onPressed: enabled ? () {} : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primary,
        disabledForegroundColor: c.textDim,
        side: BorderSide(color: enabled ? c.primary : c.cardBorder),
        minimumSize: const Size(0, 68),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
      ),
      child: Text(
        label,
        style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _iconButton(
    BuildContext context,
    List<List<dynamic>> icon, {
    required bool enabled,
  }) {
    final c = context.colors;
    return Container(
      height: 68,
      width: 68,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.cardBorder),
      ),
      child: Center(
        child: HugeIcon(
          icon: icon,
          color: enabled ? c.textPrimary : c.textDim,
          size: 24,
        ),
      ),
    );
  }
}
