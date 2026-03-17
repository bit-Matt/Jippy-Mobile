import 'route_point.dart';

/// A jeepney route from the dashboard API (id, number, name, color, ordered points).
class JeepneyRoute {
  const JeepneyRoute({
    required this.id,
    required this.routeNumber,
    required this.routeName,
    required this.routeColor,
    required this.routeDetail,
    required this.points,
  });

  final String id;
  final String routeNumber;
  final String routeName;
  /// Hex color string (e.g. "#009e49"). Use for polyline color; fallback if invalid.
  final String routeColor;
  /// Route details text from backend. Used by the panel details view.
  final String routeDetail;
  final List<RoutePoint> points;

  /// Parses from API shape: { "id", "routeNumber", "routeName", "routeColor", "routeDetail", "points": [] }.
  static JeepneyRoute? fromJson(Map<String, dynamic> json) {
    final pointsJson = json['points'];
    if (pointsJson is! List) return null;
    final points = <RoutePoint>[];
    for (final e in pointsJson) {
      if (e is Map<String, dynamic>) {
        final p = RoutePoint.fromJson(e);
        if (p != null) points.add(p);
      }
    }
    if (points.isEmpty) return null;

    final id = json['id']?.toString() ?? '';
    final routeNumber = json['routeNumber']?.toString() ?? '';
    final routeName = json['routeName']?.toString() ?? '';
    final routeColor = json['routeColor']?.toString() ?? '#e68c1e';
    final routeDetail = json['routeDetail']?.toString() ?? '';
    return JeepneyRoute(
      id: id,
      routeNumber: routeNumber,
      routeName: routeName,
      routeColor: routeColor,
      routeDetail: routeDetail,
      points: points,
    );
  }
}
