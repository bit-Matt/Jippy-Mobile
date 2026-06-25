import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/widgets/sticker_viewer.dart';

/// Horizontally scrollable gallery of route sticker images.
/// Renders nothing when [imageUrls] is empty.
class StickerGallery extends StatelessWidget {
  const StickerGallery({
    super.key,
    required this.imageUrls,
    required this.height,
    this.itemSpacing = 10,
  });

  final List<String> imageUrls;
  final double height;
  final double itemSpacing;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    if (imageUrls.length == 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _StickerTile(
          url: imageUrls.first,
          height: height,
          width: double.infinity,
          onTap: () => showStickerViewer(
            context,
            imageUrls: imageUrls,
            initialIndex: 0,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - itemSpacing) * 0.48;

          return SizedBox(
            height: height,
            child: ListView.separated(
              primary: false,
              scrollDirection: Axis.horizontal,
              itemCount: imageUrls.length,
              separatorBuilder: (_, _) => SizedBox(width: itemSpacing),
              itemBuilder: (context, index) {
                return _StickerTile(
                  url: imageUrls[index],
                  height: height,
                  width: itemWidth,
                  onTap: () => showStickerViewer(
                    context,
                    imageUrls: imageUrls,
                    initialIndex: index,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({
    required this.url,
    required this.height,
    required this.width,
    required this.onTap,
  });

  final String url;
  final double height;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: MapColors.primary.withValues(alpha: 0.14),
            ),
            color: MapColors.background,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MapColors.primary.withValues(alpha: 0.6),
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (context, _, _) => Icon(
                Icons.broken_image_outlined,
                color: MapColors.text.withValues(alpha: 0.35),
                size: height * 0.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
