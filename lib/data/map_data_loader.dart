import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../models/routes_and_stations_data.dart';
import '../services/connectivity_service.dart';
import '../services/offline_routes_cache_service.dart';

/// Timeout for the routes API request.
const Duration _routesApiTimeout = Duration(seconds: 15);

/// Path to the sample routes/stations JSON asset (dashboard API shape).
const String sampleRoutesAssetPath =
    'assets/sample_routes/sample_api_data.json';

/// Where [loadMapData] sourced its payload.
enum MapDataSource { api, offlineCache, sampleAsset }

/// Result of [loadMapData] including whether bundled sample data was used.
typedef MapDataLoadResult = ({
  RoutesAndStationsData data,
  MapDataSource source,
});

/// Fetches route and station data from the server API.
/// Returns parsed [RoutesAndStationsData] on success.
/// Throws on network error, non-200 response, or parse failure (caller can fall back to [loadSampleMapData]).
Future<RoutesAndStationsData> loadRoutesFromApi() async {
  final response = await http
      .get(Uri.parse(routesApiUrl))
      .timeout(_routesApiTimeout);

  if (response.statusCode != 200) {
    throw Exception('Routes API returned ${response.statusCode}');
  }

  final json = jsonDecode(response.body);
  if (json is! Map<String, dynamic>) {
    throw Exception('Routes API returned invalid JSON');
  }

  return RoutesAndStationsData.fromJson(json);
}

/// Loads route/station/region data using current connectivity.
Future<MapDataLoadResult> loadMapDataForCurrentConnectivity() {
  return loadMapData(online: ConnectivityService.instance.isOnline.value);
}

/// Loads route/station/region data: live API when online, offline cache when
/// available, otherwise bundled sample asset.
Future<MapDataLoadResult> loadMapData({required bool online}) async {
  if (!online) {
    final cached = await OfflineRoutesCacheService.instance.loadCached();
    if (cached != null) {
      return (data: cached, source: MapDataSource.offlineCache);
    }
    return (
      data: await loadSampleMapData(),
      source: MapDataSource.sampleAsset,
    );
  }

  try {
    return (
      data: await loadRoutesFromApi(),
      source: MapDataSource.api,
    );
  } catch (_) {
    final cached = await OfflineRoutesCacheService.instance.loadCached();
    if (cached != null) {
      return (data: cached, source: MapDataSource.offlineCache);
    }
    return (
      data: await loadSampleMapData(),
      source: MapDataSource.sampleAsset,
    );
  }
}

/// Loads the sample map data from assets and parses it into [RoutesAndStationsData].
/// Returns empty data on load or parse error.
Future<RoutesAndStationsData> loadSampleMapData() async {
  try {
    final String jsonString = await rootBundle.loadString(
      sampleRoutesAssetPath,
    );
    final Map<String, dynamic> json =
        jsonDecode(jsonString) as Map<String, dynamic>;
    return RoutesAndStationsData.fromJson(json);
  } catch (_) {
    return const RoutesAndStationsData(
      routes: [],
      stations: [],
      regions: [],
      closures: [],
    );
  }
}
