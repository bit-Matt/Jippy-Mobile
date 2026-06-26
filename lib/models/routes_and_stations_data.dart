import 'jeepney_route.dart';
import 'road_closure.dart';
import 'tricycle_region.dart';
import 'tricycle_station.dart';

/// Parsed dashboard API data: routes, stations, regions, and road closures.
class RoutesAndStationsData {
  const RoutesAndStationsData({
    required this.routes,
    required this.stations,
    required this.regions,
    required this.closures,
  });

  final List<JeepneyRoute> routes;
  final List<TricycleStation> stations;
  final List<TricycleRegion> regions;
  final List<RoadClosure> closures;

  /// Parses from API root:
  /// { "ok", "data": { "routes": [], "regions": [], "closures": [] } }.
  /// Returns empty data if structure is invalid; skips malformed entries.
  static RoutesAndStationsData fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      return const RoutesAndStationsData(
        routes: [],
        stations: [],
        regions: [],
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

    final regions = <TricycleRegion>[];
    final stations = <TricycleStation>[];
    final regionsList = data['regions'];
    if (regionsList is List) {
      for (final region in regionsList) {
        if (region is Map<String, dynamic>) {
          final parsedRegion = TricycleRegion.fromJson(region);
          if (parsedRegion != null) {
            regions.add(parsedRegion);
            stations.addAll(parsedRegion.stations);
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
      regions: regions,
      closures: closures,
    );
  }
}
