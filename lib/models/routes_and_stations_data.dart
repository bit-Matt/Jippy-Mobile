import 'jeepney_route.dart';
import 'road_closure.dart';
import 'tricycle_station.dart';

/// Parsed dashboard API data: routes, stations, and road closures.
class RoutesAndStationsData {
  const RoutesAndStationsData({
    required this.routes,
    required this.stations,
    required this.closures,
  });

  final List<JeepneyRoute> routes;
  final List<TricycleStation> stations;
  final List<RoadClosure> closures;

  /// Parses from API root:
  /// { "ok", "data": { "routes": [], "regions": [ { "stations": [] } ], "closures": [] } }.
  /// Returns empty data if structure is invalid; skips malformed route/station/closure entries.
  static RoutesAndStationsData fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      return const RoutesAndStationsData(
        routes: [],
        stations: [],
        closures: [],
      );
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

    final closures = <RoadClosure>[];
    final closuresList = data['closures'] ?? data['closure'];
    if (closuresList is List) {
      for (final e in closuresList) {
        if (e is Map<String, dynamic>) {
          final closure = RoadClosure.fromJson(e);
          if (closure != null) closures.add(closure);
        }
      }
    }

    return RoutesAndStationsData(
      routes: routes,
      stations: stations,
      closures: closures,
    );
  }
}
