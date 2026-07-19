import 'dart:io';

import 'package:flutter/material.dart';

/// Loads a remote URL or a local file path (offline cache).
class CachedNetworkOrFileImage extends StatelessWidget {
  const CachedNetworkOrFileImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.loadingSize = 22,
    this.errorIconSize = 32,
    this.loadingColor,
    this.errorIconColor,
  });

  final String url;
  final BoxFit fit;
  final double loadingSize;
  final double errorIconSize;
  final Color? loadingColor;
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
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedErrorColor =
        errorIconColor ?? colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final resolvedLoadingColor =
        loadingColor ?? colorScheme.primary.withValues(alpha: 0.6);

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
              color: resolvedLoadingColor,
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
