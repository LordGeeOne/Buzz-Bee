import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../services/connection_service.dart';
import '../theme/nexaryo_colors.dart';

class StyleGuideHome extends StatelessWidget {
  final Function(int) onNavigate;

  const StyleGuideHome({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _sectionCard(
            context,
            icon: HugeIcons.strokeRoundedVibrate,
            title: 'Buzz Bee',
            description: "vibrate your partner's phone",
            index: 1,
            badge: _BuzzBeeBadge(),
          ),
          _sectionCard(
            context,
            icon: HugeIcons.strokeRoundedImage01,
            title: 'Buzz Pic',
            description: 'send a quick picture',
            index: 2,
          ),
          _sectionCard(
            context,
            icon: HugeIcons.strokeRoundedTextFont,
            title: 'Buzz Word',
            description: 'send a short message',
            index: 3,
          ),
          _sectionCard(
            context,
            icon: HugeIcons.strokeRoundedMic01,
            title: 'Buzz Voice',
            description: 'send a voice note',
            index: 4,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required List<List<dynamic>> icon,
    required String title,
    required String description,
    required int index,
    Widget? badge,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        child: InkWell(
          onTap: () => onNavigate(index),
          borderRadius: BorderRadius.circular(34),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.cardBorder),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
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
                          icon: icon,
                          color: c.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                    if (badge != null)
                      Positioned(top: -4, right: -4, child: badge),
                  ],
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
                        description,
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
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
      ),
    );
  }
}

class _BuzzBeeBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      stream: ConnectionService.myConnectionStream(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final myUid = ConnectionService.myUid;
        final unseen =
            ((data?['unseen'] as Map?)?[myUid] as num?)?.toInt() ?? 0;
        if (unseen <= 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            unseen > 99 ? '99+' : '$unseen',
            style: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
