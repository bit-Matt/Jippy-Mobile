import 'jeepney_route.dart';
import 'tricycle_station.dart';

/// Parsed dashboard API data: jeepney routes and tricycle stations (flattened from regions).
class RoutesAndStationsData {
  const RoutesAndStationsData({
    required this.routes,
    required this.stations,
  });

  final List<JeepneyRoute> routes;
  final List<TricycleStation> stations;

  /// Parses from the API root: { "ok", "data": { "routes": [], "regions": [ { "stations": [] } ] } }.
  /// Returns empty data if structure is invalid; skips malformed route/station entries.
  static RoutesAndStationsData fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      return const RoutesAndStationsData(routes: [], stations: []);
    }

    final routes = <JeepneyRoute>[];
    final routesList = data['routes'];
    if (routesList is List) {
      for (final e in routesList) {
        if (e is Map<String, dynamic>) {
          final r = JeepneyRoute.fromJson(e);
          if (r != null) routes.add(r);
        }
      }
    }

    final stations = <TricycleStation>[];
    final regionsList = data['regions'];
    if (regionsList is List) {
      for (final region in regionsList) {
        if (region is Map<String, dynamic>) {
          final stationsList = region['stations'];
          if (stationsList is List) {
            for (final e in stationsList) {
              if (e is Map<String, dynamic>) {
                final s = TricycleStation.fromJson(e);
                if (s != null) stations.add(s);
              }
            }
          }
        }
      }
    }

    return RoutesAndStationsData(routes: routes, stations: stations);
  }
}
