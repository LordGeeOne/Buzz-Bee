import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/nexaryo_colors.dart';

/// Full-screen image viewer with pinch-to-zoom.
///
/// Pass either a network [imageUrl] or a [heroTag] for hero animations.
class ImageViewerScreen extends StatelessWidget {
  final String? imageUrl;
  final String? heroTag;

  const ImageViewerScreen({super.key, this.imageUrl, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasImage = (imageUrl ?? '').isNotEmpty;

    Widget content = hasImage
        ? Image.network(
            imageUrl!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _placeholder(c),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Center(child: CircularProgressIndicator(color: c.primary));
            },
          )
        : _placeholder(c);

    if (heroTag != null) {
      content = Hero(tag: heroTag!, child: content);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(child: content),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                height: 68,
                width: 68,
                decoration: BoxDecoration(
                  color: c.card,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(NexaryoColors c) {
    return Center(
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedUser,
        color: c.textDim,
        size: 96,
      ),
    );
  }
}
