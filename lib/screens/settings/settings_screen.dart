import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../theme/nexaryo_colors.dart';
import '../splash_screen.dart';
import 'about_screen.dart';
import 'sign_out_screen.dart';
import 'notes_screen.dart';
import 'privacy_policy_screen.dart';
import 'theme_colors_screen.dart';
import 'typography_screen.dart';
import 'test_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App bar
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
                    'Settings',
                    style: GoogleFonts.montserrat(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Navigation tiles
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'APPEARANCE',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: c.textDim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _NavTile(
                    icon: HugeIcons.strokeRoundedPaintBoard,
                    title: 'Theme Colors',
                    subtitle: 'Customize the app color palette',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ThemeColorsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _NavTile(
                    icon: HugeIcons.strokeRoundedTextFont,
                    title: 'Typography',
                    subtitle: 'Browse text styles and bundled fonts',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TypographyScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'DEVELOPER',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: c.textDim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _NavTile(
                    icon: HugeIcons.strokeRoundedTestTube,
                    title: 'Test Screen',
                    subtitle: 'Component sandbox',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TestScreen()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _NavTile(
                    icon: HugeIcons.strokeRoundedNote01,
                    title: 'Notes',
                    subtitle: 'Write and save notes',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotesScreen()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _NavTile(
                    icon: HugeIcons.strokeRoundedLoading01,
                    title: 'Splash Screen',
                    subtitle: 'Preview the app launch screen',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SplashScreen(
                          onFinished: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _NavTile(
                    icon: HugeIcons.strokeRoundedLogout01,
                    title: 'Sign Out',
                    subtitle: 'Manage your account',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignOutScreen()),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'ABOUT',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: c.textDim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _NavTile(
                    icon: HugeIcons.strokeRoundedLock,
                    title: 'Privacy Policy',
                    subtitle: 'How we handle your data',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _NavTile(
                    icon: HugeIcons.strokeRoundedInformationCircle,
                    title: 'About',
                    subtitle: 'App info & contact',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
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

class _NavTile extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(34),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  borderRadius: BorderRadius.circular(34),
                ),
                child: Center(
                  child: HugeIcon(icon: icon, color: c.textSecondary, size: 20),
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
                        fontSize: 13,
                        color: c.textDim,
                      ),
                    ),
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
  }
}
