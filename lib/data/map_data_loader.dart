import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../models/routes_and_stations_data.dart';
import '../services/connectivity_service.dart';
import '../services/entitlement_service.dart';
import '../services/offline_routes_cache_service.dart';

/// Timeout for the routes API request.
const Duration _routesApiTimeout = Duration(seconds: 15);

/// Empty map payload when no live or cached data is available.
const emptyMapData = RoutesAndStationsData(
  routes: [],
  stations: [],
  regions: [],
  closures: [],
);

/// Where [loadMapData] sourced its payload.
enum MapDataSource { api, offlineCache }

/// Result of [loadMapData] including data source.
typedef MapDataLoadResult = ({
  RoutesAndStationsData data,
  MapDataSource source,
});

/// Fetches route and station data from the server API.
/// Returns parsed [RoutesAndStationsData] on success.
/// Throws on network error, non-200 response, or parse failure.
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
Future<MapDataLoadResult> loadMapDataForCurrentConnectivity({
  bool? premiumUnlocked,
}) {
  return loadMapData(
    online: ConnectivityService.instance.isOnline.value,
    premiumUnlocked: premiumUnlocked,
  );
}

/// Loads route/station/region data: live API when online, premium-gated offline
/// cache when available, otherwise empty data.
Future<MapDataLoadResult> loadMapData({
  required bool online,
  bool? premiumUnlocked,
}) async {
  final hasPremium =
      premiumUnlocked ?? EntitlementService.instance.premiumUnlocked;

  if (!online) {
    if (hasPremium) {
      final cached = await OfflineRoutesCacheService.instance.loadCached();
      if (cached != null) {
        return (data: cached, source: MapDataSource.offlineCache);
      }
    }
    return (data: emptyMapData, source: MapDataSource.offlineCache);
  }

  try {
    return (
      data: await loadRoutesFromApi(),
      source: MapDataSource.api,
    );
  } catch (_) {
    if (hasPremium) {
      final cached = await OfflineRoutesCacheService.instance.loadCached();
      if (cached != null) {
        return (data: cached, source: MapDataSource.offlineCache);
      }
    }
    return (data: emptyMapData, source: MapDataSource.offlineCache);
  }
}
