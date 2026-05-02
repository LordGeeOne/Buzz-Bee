import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/nexaryo_colors.dart';

class ThemeColorsScreen extends StatelessWidget {
  const ThemeColorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Container(
                    height: 68,
                    width: 68,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(34),
                    ),
                    child: IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowLeft01,
                        color: c.textDim,
                        size: 24,
                      ),
                      iconSize: 24,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Theme',
                    style: GoogleFonts.montserrat(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 8),
                  _SectionLabel('MODE'),
                  const SizedBox(height: 12),
                  const _ModeToggle(),
                  const SizedBox(height: 28),
                  _SectionLabel('PALETTE'),
                  const SizedBox(height: 12),
                  ...NexaryoColors.palettes.map(
                    (p) => _ThemePaletteCard(palette: p),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: context.colors.textDim,
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle();

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              borderRadius: BorderRadius.circular(34),
            ),
            child: Center(
              child: HugeIcon(
                icon: tp.isDark
                    ? HugeIcons.strokeRoundedSun01
                    : HugeIcons.strokeRoundedMoon,
                color: c.textSecondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              tp.isDark ? 'Light Mode' : 'Dark Mode',
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          Switch(
            value: tp.isDark,
            onChanged: context.read<ThemeProvider>().setDarkMode,
            activeThumbColor: c.primary,
            inactiveTrackColor: c.cardBorder,
          ),
        ],
      ),
    );
  }
}

class _ThemePaletteCard extends StatelessWidget {
  final NexaryoPalette palette;
  const _ThemePaletteCard({required this.palette});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final c = context.colors;
    final isSelected = tp.activeId == palette.id;
    final preview = tp.isDark ? palette.dark : palette.light;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => context.read<ThemeProvider>().setTheme(palette.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: isSelected ? c.primary : c.cardBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Color preview swatch
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    children: [
                      Container(color: preview.background),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 28,
                        child: Container(color: preview.primary),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        width: 14,
                        height: 14,
                        child: Container(color: preview.accentWarm),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      palette.name,
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _dot(preview.primary),
                        const SizedBox(width: 6),
                        _dot(preview.accentWarm),
                        const SizedBox(width: 6),
                        _dot(preview.card),
                        const SizedBox(width: 6),
                        _dot(preview.textPrimary),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isSelected)
                HugeIcon(
                  icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                  color: c.primary,
                  size: 24,
                )
              else
                const SizedBox(width: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black12, width: 0.5),
    ),
  );
}
