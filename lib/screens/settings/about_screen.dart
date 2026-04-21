import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/nexaryo_colors.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
                    'About',
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
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Buzz Bee',
                        style: TextStyle(
                          fontFamily: 'Miloner',
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "there's a buzz buzz buzz in the meadow",
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: c.textDim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'v1.0.0',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          color: c.textDim,
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        'Developed by',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: c.textDim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'NEXARYO',
                        style: TextStyle(
                          fontFamily: 'Miloner',
                          fontSize: 22,
                          letterSpacing: 3,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      GestureDetector(
                        onTap: () =>
                            launchUrl(Uri.parse('mailto:admin@nexaryo.co.za')),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedMail01,
                              color: c.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'admin@nexaryo.co.za',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                color: c.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        '© 2026 Nexaryo. All rights reserved.',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: c.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
