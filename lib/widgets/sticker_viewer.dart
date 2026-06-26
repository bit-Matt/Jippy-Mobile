import 'package:flutter/material.dart';

import 'cached_network_or_file_image.dart';

/// Opens a full-screen modal to view sticker images with pinch-to-zoom.
/// Tap outside the image area to dismiss. Swipe horizontally when multiple images.
Future<void> showStickerViewer(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
}) {
  if (imageUrls.isEmpty) return Future.value();

  final safeIndex = initialIndex.clamp(0, imageUrls.length - 1);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss sticker viewer',
    barrierColor: Colors.black.withValues(alpha: 0.82),
    pageBuilder: (dialogContext, _, _) {
      return _StickerViewerDialog(
        imageUrls: imageUrls,
        initialIndex: safeIndex,
      );
    },
  );
}

class _StickerViewerDialog extends StatefulWidget {
  const _StickerViewerDialog({
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<_StickerViewerDialog> createState() => _StickerViewerDialogState();
}

class _StickerViewerDialogState extends State<_StickerViewerDialog> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showIndicator = widget.imageUrls.length > 1;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 48,
                    ),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: CachedNetworkOrFileImage(
                        url: widget.imageUrls[index],
                        fit: BoxFit.contain,
                        loadingSize: 48,
                        errorIconSize: 64,
                        loadingColor: Colors.white,
                        errorIconColor: Colors.white54,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close',
              ),
            ),
            if (showIndicator)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Text(
                  '${_currentIndex + 1} / ${widget.imageUrls.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
