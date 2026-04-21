import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/nexaryo_colors.dart';
import '../../widgets/section_header.dart';

class NamingConventionsSection extends StatelessWidget {
  const NamingConventionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Naming Conventions',
            description: 'Consistent naming across all Nexaryo apps.',
          ),

          _conventionCard(context, 'Files', 'snake_case.dart', [
            'settings_screen.dart',
            'app_colors.dart',
            'task_provider.dart',
            'now_playing_bar.dart',
          ]),
          const SizedBox(height: 12),

          _conventionCard(context, 'Classes & Widgets', 'PascalCase', [
            'SettingsScreen',
            'AppColors',
            'TaskProvider',
            'NowPlayingBar',
          ]),
          const SizedBox(height: 12),

          _conventionCard(context, 'Variables & Methods', 'camelCase', [
            'userName',
            'oneHandedMode',
            'filterSubject',
            '_scrollController',
          ]),
          const SizedBox(height: 12),

          _conventionCard(context, 'Constants', 'camelCase (static const)', [
            'AppColors.background',
            'AppColors.primary',
            'AppTextStyles.heading1',
          ]),
          const SizedBox(height: 12),

          _conventionCard(context, 'Providers', '[Domain]Provider', [
            'SettingsProvider',
            'TaskProvider',
            'SessionProvider',
          ]),
          const SizedBox(height: 12),

          _conventionCard(
            context,
            'Screens',
            '[Feature]Screen in [feature]_screen.dart',
            [
              'DashboardScreen → dashboard_screen.dart',
              'SettingsScreen → settings_screen.dart',
              'PlayerScreen → player_screen.dart',
            ],
          ),
          const SizedBox(height: 12),

          _conventionCard(context, 'Private State Classes', '_[Widget]State', [
            '_DashboardScreenState',
            '_InputsSectionState',
          ]),
          const SizedBox(height: 12),

          _conventionCard(
            context,
            'Screen-Local Widgets',
            '_[name] (private, in same file or widgets/ subfolder)',
            ['_AppBarDelegate', '_buildAppBarRow()', '_sectionCard()'],
          ),
          const SizedBox(height: 24),

          _ruleCard(
            context,
            'Prefixes',
            '• Private members start with _\n'
                '• No Hungarian notation (no strName, boolFlag)\n'
                '• Boolean getters read as questions: isPlaying, hasData, oneHandedMode',
          ),
          const SizedBox(height: 12),

          _ruleCard(
            context,
            'Import Order',
            '1. dart: packages\n'
                '2. package: (Flutter SDK)\n'
                '3. package: (third-party)\n'
                '4. Relative imports (../../)\n\n'
                'Each group separated by a blank line.',
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _conventionCard(
    BuildContext context,
    String category,
    String pattern,
    List<String> examples,
  ) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                category,
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(34),
                ),
                child: Text(
                  pattern,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...examples.map(
            (ex) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.textDim,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ex,
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleCard(BuildContext context, String title, String body) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.cardBorder),
      ),
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
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              height: 1.6,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
