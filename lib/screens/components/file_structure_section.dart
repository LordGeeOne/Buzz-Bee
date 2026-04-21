import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/nexaryo_colors.dart';
import '../../widgets/section_header.dart';

class FileStructureSection extends StatelessWidget {
  const FileStructureSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'File Structure',
            description: 'Standard project layout for all Nexaryo apps.',
          ),

          _treeBlock(context, 'Project Root', [
            'lib/',
            '  main.dart',
            '  providers/',
            '    settings_provider.dart',
            '    [feature]_provider.dart',
            '  models/',
            '    [model_name].dart',
            '  services/',
            '    [service_name].dart',
            '  screens/',
            '    [feature]/',
            '      [feature]_screen.dart',
            '      widgets/',
            '        [widget_name].dart',
            '    settings/',
            '      settings_screen.dart',
            '      privacy_policy_screen.dart',
            '  theme/',
            '    app_colors.dart',
            '    app_text_styles.dart',
            '  utils/',
            '    [utility_name].dart',
            '  widgets/',
            '    [shared_widget].dart',
          ]),
          const SizedBox(height: 24),

          _ruleCard(
            context,
            'Screens',
            'Each feature gets its own folder under screens/. '
                'Screen-specific widgets go in a widgets/ subfolder within the feature. '
                'Only truly shared widgets go in the top-level widgets/ folder.',
          ),
          const SizedBox(height: 12),
          _ruleCard(
            context,
            'Providers',
            'One provider per domain concern. SettingsProvider is always present '
                'for app-wide preferences (one-handed mode, user name, etc.).',
          ),
          const SizedBox(height: 12),
          _ruleCard(
            context,
            'Theme',
            'app_colors.dart and app_text_styles.dart are the only theme files. '
                'All colors come from AppColors, all text styles from AppTextStyles or GoogleFonts.montserrat().',
          ),
          const SizedBox(height: 12),
          _ruleCard(
            context,
            'Models',
            'Plain Dart classes. No business logic — just data fields, '
                'fromJson/toJson, and copyWith when needed.',
          ),
          const SizedBox(height: 12),
          _ruleCard(
            context,
            'Services',
            'Storage, API, and platform abstractions. Services have no UI dependency '
                'and are injected via provider or constructed in main.',
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _treeBlock(BuildContext context, String title, List<String> lines) {
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
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...lines.map((line) {
            final isFolder = line.trimLeft().endsWith('/');
            final isBracket = line.contains('[');
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: isBracket
                      ? c.textDim
                      : isFolder
                      ? c.primary
                      : c.textSecondary,
                ),
              ),
            );
          }),
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
