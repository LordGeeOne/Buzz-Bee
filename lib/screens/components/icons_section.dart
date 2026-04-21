import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../theme/nexaryo_colors.dart';
import '../../widgets/section_header.dart';

class IconsSection extends StatelessWidget {
  const IconsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = [
      _IconCategory('Navigation', [
        _IconEntry(HugeIcons.strokeRoundedHome01, 'Home01'),
        _IconEntry(HugeIcons.strokeRoundedArrowLeft01, 'ArrowLeft01'),
        _IconEntry(HugeIcons.strokeRoundedArrowRight01, 'ArrowRight01'),
        _IconEntry(HugeIcons.strokeRoundedMenu01, 'Menu01'),
        _IconEntry(HugeIcons.strokeRoundedCancel01, 'Cancel01'),
        _IconEntry(HugeIcons.strokeRoundedMoreVertical, 'MoreVertical'),
        _IconEntry(HugeIcons.strokeRoundedArrowRight02, 'ArrowRight02'),
        _IconEntry(HugeIcons.strokeRoundedArrowDown01, 'ArrowDown01'),
      ]),
      _IconCategory('Actions', [
        _IconEntry(HugeIcons.strokeRoundedAdd01, 'Add01'),
        _IconEntry(HugeIcons.strokeRoundedEdit02, 'Edit02'),
        _IconEntry(HugeIcons.strokeRoundedDelete01, 'Delete01'),
        _IconEntry(HugeIcons.strokeRoundedSearch01, 'Search01'),
        _IconEntry(HugeIcons.strokeRoundedShare01, 'Share01'),
        _IconEntry(HugeIcons.strokeRoundedCopy01, 'Copy01'),
        _IconEntry(HugeIcons.strokeRoundedTick01, 'Tick01'),
        _IconEntry(HugeIcons.strokeRoundedRefresh, 'Refresh'),
      ]),
      _IconCategory('Media', [
        _IconEntry(HugeIcons.strokeRoundedPlay, 'Play'),
        _IconEntry(HugeIcons.strokeRoundedPause, 'Pause'),
        _IconEntry(HugeIcons.strokeRoundedNext, 'Next'),
        _IconEntry(HugeIcons.strokeRoundedPrevious, 'Previous'),
        _IconEntry(HugeIcons.strokeRoundedShuffle, 'Shuffle'),
        _IconEntry(HugeIcons.strokeRoundedRepeat, 'Repeat'),
        _IconEntry(HugeIcons.strokeRoundedVolumeHigh, 'VolumeHigh'),
        _IconEntry(HugeIcons.strokeRoundedMusicNote01, 'MusicNote01'),
      ]),
      _IconCategory('Communication', [
        _IconEntry(HugeIcons.strokeRoundedNotification01, 'Notification01'),
        _IconEntry(HugeIcons.strokeRoundedMail01, 'Mail01'),
        _IconEntry(HugeIcons.strokeRoundedChat01, 'Chat01'),
        _IconEntry(HugeIcons.strokeRoundedUser, 'User'),
        _IconEntry(HugeIcons.strokeRoundedUserGroup, 'UserGroup'),
        _IconEntry(HugeIcons.strokeRoundedMailSend01, 'MailSend01'),
      ]),
      _IconCategory('Settings & System', [
        _IconEntry(HugeIcons.strokeRoundedSettings01, 'Settings01'),
        _IconEntry(HugeIcons.strokeRoundedInformationCircle, 'InfoCircle'),
        _IconEntry(HugeIcons.strokeRoundedHelpCircle, 'HelpCircle'),
        _IconEntry(HugeIcons.strokeRoundedMoon, 'Moon'),
        _IconEntry(HugeIcons.strokeRoundedGlobe, 'Globe'),
        _IconEntry(HugeIcons.strokeRoundedLock, 'Lock'),
      ]),
      _IconCategory('Favorites', [
        _IconEntry(HugeIcons.strokeRoundedHeartCheck, 'HeartCheck'),
        _IconEntry(HugeIcons.strokeRoundedStar, 'Star'),
        _IconEntry(HugeIcons.strokeRoundedSettings02, 'Settings02'),
        _IconEntry(HugeIcons.strokeRoundedBellDot, 'BellDot'),
        _IconEntry(HugeIcons.strokeRoundedUserCircle, 'UserCircle'),
        _IconEntry(HugeIcons.strokeRoundedHome02, 'Home02'),
      ]),
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Icons',
            description:
                'Rounded Material icons and Cupertino icons used across Nexaryo apps.',
          ),
          ...categories.map((cat) => _buildCategory(context, cat)),
        ],
      ),
    );
  }

  Widget _buildCategory(BuildContext context, _IconCategory category) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category.name,
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: category.icons
                .map((e) => _buildIconTile(context, e))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildIconTile(BuildContext context, _IconEntry entry) {
    final c = context.colors;
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        children: [
          HugeIcon(icon: entry.icon, color: c.textPrimary, size: 26),
          const SizedBox(height: 8),
          Text(
            entry.name,
            style: GoogleFonts.montserrat(fontSize: 9, color: c.textDim),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _IconCategory {
  final String name;
  final List<_IconEntry> icons;
  _IconCategory(this.name, this.icons);
}

class _IconEntry {
  final List<List<dynamic>> icon;
  final String name;
  _IconEntry(this.icon, this.name);
}
