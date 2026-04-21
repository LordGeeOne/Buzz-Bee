import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../theme/nexaryo_colors.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/section_header.dart';

class PatternsSection extends StatelessWidget {
  const PatternsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Patterns',
            description:
                'Reusable architecture patterns shared across all Nexaryo apps.',
          ),

          // One-Handed Mode
          _patternCard(
            context,
            title: 'One-Handed Mode',
            icon: HugeIcons.strokeRoundedSmartPhone01,
            description:
                'Pushes content down by 40% of screen height so users can reach '
                'everything with one hand. Uses a SliverPersistentHeader that pins '
                'seamlessly at the top when scrolled up.',
            codeSnippet: '''// In your screen's build():
final screenHeight = MediaQuery.of(context).size.height;
final settings = context.watch<SettingsProvider>();
final topPadding = settings.oneHandedMode
    ? screenHeight * 0.4 : 0.0;

CustomScrollView(
  slivers: [
    if (settings.oneHandedMode)
      SliverToBoxAdapter(
        child: SizedBox(height: topPadding),
      ),
    SliverPersistentHeader(
      pinned: true,
      delegate: _AppBarDelegate(child: appBar),
    ),
    // ... content slivers
  ],
);''',
            interactive: _OneHandedDemo(),
          ),
          const SizedBox(height: 16),

          // State Management
          _patternCard(
            context,
            title: 'State Management',
            icon: HugeIcons.strokeRoundedFlowConnection,
            description:
                'Provider + ChangeNotifier for all state. Providers are created '
                'in main.dart and injected via ChangeNotifierProvider. Screens '
                'consume state with context.watch<T>() and fire actions with '
                'context.read<T>().',
            codeSnippet: '''// Provider definition
class SettingsProvider extends ChangeNotifier {
  bool _oneHandedMode = false;
  bool get oneHandedMode => _oneHandedMode;

  set oneHandedMode(bool value) {
    _oneHandedMode = value;
    notifyListeners();
    _save();
  }
}

// In main.dart
ChangeNotifierProvider.value(
  value: settings,
  child: MaterialApp(...),
);

// In a widget
final settings = context.watch<SettingsProvider>();
// or for actions:
context.read<SettingsProvider>().oneHandedMode = true;''',
          ),
          const SizedBox(height: 16),

          // Navigation
          _patternCard(
            context,
            title: 'Navigation',
            icon: HugeIcons.strokeRoundedRoute01,
            description:
                'Named routes for feature screens. In-screen navigation uses '
                'index-based page switching (no nested Navigator). '
                'Back buttons call the parent navigate function.',
            codeSnippet: '''// Named routes (for multi-screen features)
Navigator.pushNamed(context, '/settings');
Navigator.pushNamed(context, '/create-task',
    arguments: filterSubject);

// Index-based (for tabbed/sectioned UIs)
void _navigate(int index) {
  setState(() => _currentIndex = index);
}''',
          ),
          const SizedBox(height: 16),

          // App Bar Pattern
          _patternCard(
            context,
            title: 'Pinned App Bar',
            icon: HugeIcons.strokeRoundedAlignTop,
            description:
                'Uses SliverPersistentHeader instead of a regular AppBar. '
                'This allows the app bar to scroll with content in one-handed mode '
                'but pin at the top when the user scrolls up.',
            codeSnippet: '''class _AppBarDelegate
    extends SliverPersistentHeaderDelegate {
  final Widget child;
  _AppBarDelegate({required this.child});

  @override double get minExtent => 56;
  @override double get maxExtent => 56;

  @override
  Widget build(BuildContext context,
      double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 4),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _AppBarDelegate old)
      => true;
}''',
          ),
          const SizedBox(height: 16),

          // Persistence
          _patternCard(
            context,
            title: 'Local Persistence',
            icon: HugeIcons.strokeRoundedFloppyDisk,
            description:
                'SharedPreferences for simple key-value data (settings, flags). '
                'Providers call _save() internally after mutations — the UI never '
                'calls save directly.',
            codeSnippet: '''Future<void> load() async {
  final prefs = await SharedPreferences.getInstance();
  _oneHandedMode =
      prefs.getBool('oneHandedMode') ?? false;
  notifyListeners();
}

Future<void> _save() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(
      'oneHandedMode', _oneHandedMode);
}''',
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _patternCard(
    BuildContext context, {
    required String title,
    required List<List<dynamic>> icon,
    required String description,
    required String codeSnippet,
    Widget? interactive,
  }) {
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(34),
                ),
                child: HugeIcon(icon: icon, color: c.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              height: 1.6,
              color: c.textSecondary,
            ),
          ),
          if (interactive != null) ...[const SizedBox(height: 16), interactive],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.cardBorder),
            ),
            child: Text(
              codeSnippet,
              style: GoogleFonts.montserrat(
                fontSize: 11,
                height: 1.6,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OneHandedDemo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<SettingsProvider>();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.cardBorder),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: settings.oneHandedMode
                ? HugeIcons.strokeRoundedSmartPhone01
                : HugeIcons.strokeRoundedSmartPhone02,
            color: settings.oneHandedMode ? c.primary : c.textDim,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'One-Handed Mode',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  settings.oneHandedMode
                      ? 'Enabled — try scrolling up'
                      : 'Disabled',
                  style: GoogleFonts.montserrat(fontSize: 12, color: c.textDim),
                ),
              ],
            ),
          ),
          Switch(
            value: settings.oneHandedMode,
            activeColor: c.primary,
            onChanged: (v) {
              context.read<SettingsProvider>().oneHandedMode = v;
            },
          ),
        ],
      ),
    );
  }
}
