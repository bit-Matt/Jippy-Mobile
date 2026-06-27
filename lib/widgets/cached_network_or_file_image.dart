import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/map_colors.dart';

/// Loads a remote URL or a local file path (offline cache).
class CachedNetworkOrFileImage extends StatelessWidget {
  const CachedNetworkOrFileImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.loadingSize = 22,
    this.errorIconSize = 32,
    this.loadingColor = Colors.white,
    this.errorIconColor,
  });

  final String url;
  final BoxFit fit;
  final double loadingSize;
  final double errorIconSize;
  final Color loadingColor;
  final Color? errorIconColor;

  bool get _isLocalFile {
    if (url.isEmpty) return false;
    if (url.startsWith('file://')) return true;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return false;
    }
    return File(url).existsSync();
  }

  String get _localPath {
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedErrorColor =
        errorIconColor ?? MapColors.text.withValues(alpha: 0.35);

    if (_isLocalFile) {
      return Image.file(
        File(_localPath),
        fit: fit,
        errorBuilder: (context, _, _) => Icon(
          Icons.broken_image_outlined,
          color: resolvedErrorColor,
          size: errorIconSize,
        ),
      );
    }

    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: loadingSize,
            height: loadingSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: loadingColor == Colors.white
                  ? loadingColor
                  : MapColors.primary.withValues(alpha: 0.6),
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
        color: resolvedErrorColor,
        size: errorIconSize,
      ),
    );
  }
}
