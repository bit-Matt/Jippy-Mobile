/// Download phase for the combined offline package.
enum OfflineDownloadPhase { routesData, mapTiles }

/// Download state for the Iloilo City offline map region.
sealed class OfflineMapStatus {
  const OfflineMapStatus();
}

class OfflineMapNotDownloaded extends OfflineMapStatus {
  const OfflineMapNotDownloaded();
}

class OfflineMapDownloading extends OfflineMapStatus {
  const OfflineMapDownloading({
    required this.progress,
    required this.phase,
    required this.loadedTiles,
    required this.totalTiles,
    required this.loadedBytes,
    this.routesImagesDownloaded = 0,
    this.routesImagesTotal = 0,
  });

  final double? progress;
  final OfflineDownloadPhase phase;
  final int loadedTiles;
  final int totalTiles;
  final int loadedBytes;
  final int routesImagesDownloaded;
  final int routesImagesTotal;
}

class OfflineMapDownloaded extends OfflineMapStatus {
  const OfflineMapDownloaded({required this.regionId});

  final int regionId;
}

class OfflineMapError extends OfflineMapStatus {
  const OfflineMapError({required this.message});

  final String message;
}

class OfflineMapUnsupported extends OfflineMapStatus {
  const OfflineMapUnsupported();
}
