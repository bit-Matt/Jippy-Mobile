import 'route_point.dart';

/// A jeepney route from the dashboard API (id, number, name, color, points by direction).
class JeepneyRoute {
  const JeepneyRoute({
    required this.id,
    required this.routeNumber,
    required this.routeName,
    required this.routeColor,
    required this.routeDetails,
    required this.goingTo,
    required this.goingBack,
  });

  final String id;
  final String routeNumber;
  final String routeName;
  /// Hex color string (e.g. "#009e49"). Use for polyline color; fallback if invalid.
  final String routeColor;
  /// Route details text from backend. Used by the panel details view.
  final String routeDetails;
  /// Outbound direction points (e.g. terminal A → terminal B).
  final List<RoutePoint> goingTo;
  /// Return direction points (e.g. terminal B → terminal A).
  final List<RoutePoint> goingBack;

  /// Backward-compatible alias for older call sites.
  String get routeDetail => routeDetails;

  /// Combined points view for legacy consumers.
  List<RoutePoint> get points => [...goingTo, ...goingBack];

  /// Parses from API shape: { "id", "routeNumber", "routeName", "routeColor", "points": { "goingTo": [], "goingBack": [] } }
  /// or legacy { "points": [] } (single list used as goingTo, goingBack empty).
  static JeepneyRoute? fromJson(Map<String, dynamic> json) {
    final pointsJson = json['points'];
    List<RoutePoint> goingTo;
    List<RoutePoint> goingBack;
    if (pointsJson is Map<String, dynamic>) {
      goingTo = _parsePointList(pointsJson['goingTo']);
      goingBack = _parsePointList(pointsJson['goingBack']);
    } else if (pointsJson is List) {
      goingTo = _parsePointList(pointsJson);
      goingBack = [];
    } else {
      return null;
    }
    if (goingTo.isEmpty && goingBack.isEmpty) return null;

    final id = json['id']?.toString() ?? '';
    final routeNumber = json['routeNumber']?.toString() ?? '';
    final routeName = json['routeName']?.toString() ?? '';
    final routeColor = json['routeColor']?.toString() ?? '#e68c1e';
    final routeDetails =
        json['routeDetails']?.toString() ?? json['routeDetail']?.toString() ?? '';
    return JeepneyRoute(
      id: id,
      routeNumber: routeNumber,
      routeName: routeName,
      routeColor: routeColor,
      routeDetails: routeDetails,
      goingTo: goingTo,
      goingBack: goingBack,
    );
  }

  static List<RoutePoint> _parsePointList(dynamic value) {
    if (value is! List) return [];
    final list = <RoutePoint>[];
    for (final e in value) {
      if (e is Map<String, dynamic>) {
        final p = RoutePoint.fromJson(e);
        if (p != null) list.add(p);
      }
    }
    return list;
  }
}
