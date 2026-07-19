import 'package:flutter/material.dart';

import 'package:jippy_mobile/widgets/cached_network_or_file_image.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

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
            border: Border.all(color: colorScheme.outlineVariant),
            color: colorScheme.surfaceContainerHighest,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: CachedNetworkOrFileImage(
              url: url,
              fit: BoxFit.contain,
              loadingSize: 22,
              errorIconSize: height * 0.35,
            ),
          ),
        ),
      ),
    );
  }
}
