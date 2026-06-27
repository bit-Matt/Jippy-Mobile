import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:maplibre/maplibre.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/map_config.dart';
import '../models/offline_map_status.dart';
import '../utils/map_coords.dart';
import 'notification_service.dart';
import 'offline_routes_cache_service.dart';

const String _regionIdPrefsKey = 'offline_map_iloilo_region_id';
const int _offlineTileCountLimit = 100000;
const double _routesProgressWeight = 0.15;

/// Manages MapLibre offline vector tile downloads and routes/regions cache for Iloilo City.
class OfflineMapService {
  OfflineMapService._();

  static final OfflineMapService instance = OfflineMapService._();

  final ValueNotifier<OfflineMapStatus> status =
      ValueNotifier<OfflineMapStatus>(const OfflineMapNotDownloaded());

  OfflineManager? _manager;
  StreamSubscription<DownloadProgress>? _downloadSubscription;
  bool _initialized = false;
  double _routesPhaseProgress = 0;

  bool get isSupported => OfflineManager.isSupported;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (!isSupported) {
      status.value = const OfflineMapUnsupported();
      return;
    }

    _manager = await OfflineManager.createInstance();
    await refreshRegionList();
  }

  Future<void> refreshRegionList() async {
    if (!isSupported || _manager == null) return;

    final regions = await _manager!.listOfflineRegions();
    OfflineRegion? iloiloRegion;
    for (final region in regions) {
      if (_isIloiloRegion(region)) {
        iloiloRegion = region;
        break;
      }
    }

    final hasRoutesCache = await OfflineRoutesCacheService.instance.hasCachedData();

    if (iloiloRegion != null && hasRoutesCache) {
      await _persistRegionId(iloiloRegion.id);
      if (status.value is! OfflineMapDownloading) {
        status.value = OfflineMapDownloaded(regionId: iloiloRegion.id);
      }
    } else {
      if (iloiloRegion == null) {
        await _clearRegionId();
      }
      if (status.value is! OfflineMapDownloading) {
        status.value = const OfflineMapNotDownloaded();
      }
    }
  }

  Future<bool> hasDownloadedRegion() async {
    if (!isSupported) return false;
    final current = status.value;
    if (current is OfflineMapDownloaded) return true;
    await refreshRegionList();
    return status.value is OfflineMapDownloaded;
  }

  Future<void> downloadIloiloRegion({required double pixelDensity}) async {
    if (!isSupported || _manager == null) return;
    if (status.value is OfflineMapDownloading) return;

    if (status.value is OfflineMapDownloaded) {
      await deleteIloiloRegion();
    }

    _routesPhaseProgress = 0;
    status.value = const OfflineMapDownloading(
      progress: 0,
      phase: OfflineDownloadPhase.routesData,
      loadedTiles: 0,
      totalTiles: 0,
      loadedBytes: 0,
    );

    try {
      await OfflineRoutesCacheService.instance.downloadAndCache(
        onProgress: (progress, imagesDone, imagesTotal) {
          _routesPhaseProgress = progress;
          _emitCombinedProgress(
            phase: OfflineDownloadPhase.routesData,
            routesImagesDownloaded: imagesDone,
            routesImagesTotal: imagesTotal,
          );
        },
      );
    } catch (error) {
      _onDownloadError(error);
      return;
    }

    await _startMapTileDownload(pixelDensity);
  }

  Future<void> _startMapTileDownload(double pixelDensity) async {
    final manager = _manager!;
    manager.setOfflineTileCountLimit(amount: _offlineTileCountLimit);

    final bounds = LngLatBounds.fromPoints([
      toGeographic(MapConfig.iloiloOfflineSouthWest),
      toGeographic(MapConfig.iloiloOfflineNorthEast),
    ]);

    status.value = OfflineMapDownloading(
      progress: _routesProgressWeight,
      phase: OfflineDownloadPhase.mapTiles,
      loadedTiles: 0,
      totalTiles: 0,
      loadedBytes: 0,
      routesImagesDownloaded: 0,
      routesImagesTotal: 0,
    );

    final stream = manager.downloadRegion(
      mapStyleUrl: MapConfig.routesStyleUrl,
      bounds: bounds,
      minZoom: MapConfig.iloiloOfflineMinZoom,
      maxZoom: MapConfig.iloiloOfflineMaxZoom,
      pixelDensity: pixelDensity,
      metadata: {'region': MapConfig.iloiloOfflineRegionKey},
    );

    await _downloadSubscription?.cancel();
    _downloadSubscription = stream.listen(
      _onMapDownloadProgress,
      onError: _onDownloadError,
      onDone: () {
        if (status.value is OfflineMapDownloading) {
          refreshRegionList();
        }
      },
    );
  }

  Future<void> deleteIloiloRegion() async {
    if (!isSupported || _manager == null) return;

    await _downloadSubscription?.cancel();
    _downloadSubscription = null;

    final prefs = await SharedPreferences.getInstance();
    final regionId = prefs.getInt(_regionIdPrefsKey);

    if (regionId != null) {
      await _manager!.deleteRegion(regionId: regionId);
    } else {
      final regions = await _manager!.listOfflineRegions();
      for (final region in regions) {
        if (_isIloiloRegion(region)) {
          await _manager!.deleteRegion(regionId: region.id);
        }
      }
    }

    await OfflineRoutesCacheService.instance.deleteCache();
    await _clearRegionId();
    status.value = const OfflineMapNotDownloaded();
  }

  void _onMapDownloadProgress(DownloadProgress update) {
    if (update.downloadCompleted) {
      unawaited(_persistRegionId(update.region.id));
      status.value = OfflineMapDownloaded(regionId: update.region.id);
      unawaited(NotificationService.instance.showOfflineMapDownloadComplete());
      return;
    }

    final tileProgress = update.progress ??
        (update.totalTiles > 0
            ? update.loadedTiles / update.totalTiles
            : null);

    _emitCombinedProgress(
      phase: OfflineDownloadPhase.mapTiles,
      tileProgress: tileProgress,
      loadedTiles: update.loadedTiles,
      totalTiles: update.totalTiles,
      loadedBytes: update.loadedBytes,
    );
  }

  void _emitCombinedProgress({
    required OfflineDownloadPhase phase,
    double? tileProgress,
    int loadedTiles = 0,
    int totalTiles = 0,
    int loadedBytes = 0,
    int routesImagesDownloaded = 0,
    int routesImagesTotal = 0,
  }) {
    final double overallProgress;
    if (phase == OfflineDownloadPhase.routesData) {
      overallProgress = _routesPhaseProgress * _routesProgressWeight;
    } else {
      final tiles = tileProgress ?? 0;
      overallProgress =
          _routesProgressWeight + tiles * (1 - _routesProgressWeight);
    }

    status.value = OfflineMapDownloading(
      progress: overallProgress,
      phase: phase,
      loadedTiles: loadedTiles,
      totalTiles: totalTiles,
      loadedBytes: loadedBytes,
      routesImagesDownloaded: routesImagesDownloaded,
      routesImagesTotal: routesImagesTotal,
    );

    final percent = (overallProgress * 100).round().clamp(0, 100);
    final body = switch (phase) {
      OfflineDownloadPhase.routesData =>
        routesImagesTotal > 0
            ? 'Routes & images: $routesImagesDownloaded / $routesImagesTotal'
            : 'Downloading routes and regions…',
      OfflineDownloadPhase.mapTiles => totalTiles > 0
          ? 'Map tiles: $loadedTiles / $totalTiles'
          : '$loadedBytes bytes downloaded',
    };

    unawaited(
      NotificationService.instance.showOfflineMapDownloadProgress(
        progress: percent,
        maxProgress: 100,
        body: body,
      ),
    );
  }

  void _onDownloadError(Object error) {
    status.value = OfflineMapError(message: error.toString());
    unawaited(
      NotificationService.instance.showOfflineMapDownloadFailed(
        error.toString(),
      ),
    );
  }

  bool _isIloiloRegion(OfflineRegion region) {
    final regionKey = region.metadata['region']?.toString();
    return regionKey == MapConfig.iloiloOfflineRegionKey;
  }

  Future<void> _persistRegionId(int regionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_regionIdPrefsKey, regionId);
  }

  Future<void> _clearRegionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_regionIdPrefsKey);
  }

  void dispose() {
    _downloadSubscription?.cancel();
    _manager?.dispose();
    status.dispose();
  }
}
