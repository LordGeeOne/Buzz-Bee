import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/image_viewer_screen.dart';
import '../theme/app_text_styles.dart';
import '../theme/nexaryo_colors.dart';

/// Photo gallery shown on a user's profile.
///
/// Stores up to [maxPhotos] image URLs in `users/{uid}.gallery` (List<String>)
/// and the underlying files at `gallery/{uid}/{millis}.jpg` in Storage.
class ProfileGallerySection extends StatefulWidget {
  final String uid;
  final List<String> photos;
  final bool isSelf;

  static const int maxPhotos = 9;

  const ProfileGallerySection({
    super.key,
    required this.uid,
    required this.photos,
    required this.isSelf,
  });

  @override
  State<ProfileGallerySection> createState() => _ProfileGallerySectionState();
}

class _ProfileGallerySectionState extends State<ProfileGallerySection> {
  final ImagePicker _picker = ImagePicker();
  final Set<int> _uploadingSlots = {};
  final Set<String> _deleting = {};

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _pickAndUpload(int slotIndex) async {
    if (_uploadingSlots.contains(slotIndex)) return;
    final source = await _chooseSource();
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1440,
        maxHeight: 1440,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
      return;
    }
    if (picked == null) return;

    setState(() => _uploadingSlots.add(slotIndex));
    try {
      final file = File(picked.path);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref('gallery/$_myUid/$fileName');
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(_myUid).set({
        'gallery': FieldValue.arrayUnion([url]),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploadingSlots.remove(slotIndex));
    }
  }

  Future<ImageSource?> _chooseSource() {
    final c = context.colors;
    final ts = context.textStyles;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Add a photo', style: ts.heading3),
              const SizedBox(height: 16),
              _SheetOption(
                label: 'Take a photo',
                icon: HugeIcons.strokeRoundedCamera01,
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _SheetOption(
                label: 'Choose from gallery',
                icon: HugeIcons.strokeRoundedImage02,
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewPhoto(String url, String heroTag) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(imageUrl: url, heroTag: heroTag),
      ),
    );
  }

  Future<void> _showSelfPhotoActions(String url, String heroTag) async {
    final c = context.colors;
    final ts = context.textStyles;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Photo', style: ts.heading3),
              const SizedBox(height: 16),
              _SheetOption(
                label: 'View photo',
                icon: HugeIcons.strokeRoundedView,
                onTap: () {
                  Navigator.pop(ctx);
                  _viewPhoto(url, heroTag);
                },
              ),
              const SizedBox(height: 8),
              _SheetOption(
                label: 'Delete photo',
                icon: HugeIcons.strokeRoundedDelete02,
                destructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(url);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String url) async {
    final c = context.colors;
    final ts = context.textStyles;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('Delete photo?', style: ts.heading3),
        content: Text(
          'This will remove the photo from your gallery.',
          style: ts.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: ts.button),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: ts.button.copyWith(color: c.accentWarm),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _deletePhoto(url);
  }

  Future<void> _deletePhoto(String url) async {
    if (_deleting.contains(url)) return;
    setState(() => _deleting.add(url));
    try {
      await FirebaseFirestore.instance.collection('users').doc(_myUid).set({
        'gallery': FieldValue.arrayRemove([url]),
      }, SetOptions(merge: true));
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {
        // Best-effort: file may already be gone, or URL may not be a
        // Firebase Storage URL.
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete photo: $e')));
    } finally {
      if (mounted) setState(() => _deleting.remove(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final photos = widget.photos.take(ProfileGallerySection.maxPhotos).toList();

    if (!widget.isSelf && photos.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(count: 0),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.cardBorder),
            ),
            child: Center(
              child: Text(
                "This user hasn't added any photos yet.",
                style: ts.bodySecondary,
              ),
            ),
          ),
        ],
      );
    }

    // Self: show filled tiles plus a single Add tile for the next slot.
    final showAddTile =
        widget.isSelf && photos.length < ProfileGallerySection.maxPhotos;
    final slotCount = photos.length + (showAddTile ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(count: photos.length),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: slotCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final hasPhoto = index < photos.length;
            if (hasPhoto) {
              final url = photos[index];
              final heroTag = 'gallery-${widget.uid}-$index';
              return _PhotoTile(
                url: url,
                heroTag: heroTag,
                deleting: _deleting.contains(url),
                onTap: widget.isSelf
                    ? () => _showSelfPhotoActions(url, heroTag)
                    : () => _viewPhoto(url, heroTag),
              );
            }
            return _AddTile(
              uploading: _uploadingSlots.contains(index),
              onTap: () => _pickAndUpload(index),
            );
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Row(
      children: [
        Expanded(
          child: Text(
            'GALLERY',
            style: ts.label.copyWith(letterSpacing: 1.2, color: c.textDim),
          ),
        ),
        Text(
          '$count / ${ProfileGallerySection.maxPhotos}',
          style: ts.caption.copyWith(color: c.textDim),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final String heroTag;
  final bool deleting;
  final VoidCallback onTap;

  const _PhotoTile({
    required this.url,
    required this.heroTag,
    required this.deleting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: c.card,
        child: InkWell(
          onTap: deleting ? null : onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: c.card,
                      child: Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: c.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, _, __) => Container(
                    color: c.card,
                    child: Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedAlertCircle,
                        color: c.textDim,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              if (deleting)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const Center(
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final bool uploading;
  final VoidCallback onTap;

  const _AddTile({required this.uploading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: uploading ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: DottedBorderBox(
          color: c.cardBorder,
          radius: 20,
          child: Center(
            child: uploading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      color: c.primary,
                      strokeWidth: 2,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedAdd01,
                        color: c.textSecondary,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text('Add', style: ts.caption),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight dashed-style border container so add slots feel different
/// from filled ones without pulling in an extra package.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;

  const DottedBorderBox({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color, width: 1.2),
      ),
      child: child,
    );
  }
}

class _SheetOption extends StatelessWidget {
  final String label;
  final List<List<dynamic>> icon;
  final VoidCallback onTap;
  final bool destructive;

  const _SheetOption({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ts = context.textStyles;
    final color = destructive ? c.accentWarm : c.textPrimary;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.cardBorder),
          ),
          child: Row(
            children: [
              HugeIcon(icon: icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: ts.bodyLarge.copyWith(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
