import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../theme/nexaryo_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
                    'Privacy Policy',
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
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Buzz Bee ("the App") is developed and maintained by Nexaryo. '
                    'This Privacy Policy explains how we handle information when you use the App.\n\n'
                    'Data Collection\n\n'
                    'The App does not collect, store, or transmit any personal data to external servers. '
                    'All data, including notes and preferences, is stored locally on your device.\n\n'
                    'Local Storage\n\n'
                    'The App uses on-device storage (SharedPreferences) to persist your settings, '
                    'theme preferences, and notes. This data never leaves your device.\n\n'
                    'Third-Party Services\n\n'
                    'The App does not integrate with any third-party analytics, advertising, '
                    'or tracking services. No data is shared with third parties.\n\n'
                    'Permissions\n\n'
                    'The App does not request access to your camera, microphone, contacts, location, '
                    'or any other sensitive device features.\n\n'
                    'Children\'s Privacy\n\n'
                    'The App does not knowingly collect any information from children. '
                    'The App is safe for users of all ages.\n\n'
                    'Changes to This Policy\n\n'
                    'We may update this Privacy Policy from time to time. '
                    'Any changes will be reflected within the App.\n\n'
                    'Contact\n\n'
                    'If you have any questions about this Privacy Policy, '
                    'please reach out to the Nexaryo development team.',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      height: 1.7,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
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
                            fontFamily: 'Beli',
                            fontSize: 18,
                            letterSpacing: 3,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
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
