import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// One polyline strand for overlap hit-testing (e.g. one route direction).
class RouteHitPolyline {
  const RouteHitPolyline({required this.routeId, required this.points});

  final String routeId;
  final List<LatLng> points;
}

/// Earth radius in meters (mean), for local equirectangular projection.
const double _earthRadiusM = 6371000.0;

/// Minimum distance from [p] to any segment of [points], in meters.
///
/// Uses a local equirectangular approximation around each segment (adequate
/// for city-scale geometry and overlap detection).
double minDistanceMetersPointToPolyline(LatLng p, List<LatLng> points) {
  if (points.length < 2) return double.infinity;
  var best = double.infinity;
  for (var i = 0; i < points.length - 1; i++) {
    final d = _pointToSegmentDistanceMeters(p, points[i], points[i + 1]);
    if (d < best) best = d;
  }
  return best;
}

/// Route IDs with at least one polyline within [thresholdMeters] of [tap].
Set<String> routeIdsNearPolylines(
  LatLng tap,
  List<RouteHitPolyline> polylines,
  double thresholdMeters,
) {
  final ids = <String>{};
  for (final pl in polylines) {
    if (pl.points.length < 2) continue;
    if (minDistanceMetersPointToPolyline(tap, pl.points) <= thresholdMeters) {
      ids.add(pl.routeId);
    }
  }
  return ids;
}

double _pointToSegmentDistanceMeters(LatLng p, LatLng a, LatLng b) {
  final latRef = (a.latitude + b.latitude + p.latitude) / 3.0;
  final cosLat = math.cos(latRef * math.pi / 180.0);

  double x(LatLng l) => _earthRadiusM * l.longitude * math.pi / 180.0 * cosLat;
  double y(LatLng l) => _earthRadiusM * l.latitude * math.pi / 180.0;

  final ax = x(a);
  final ay = y(a);
  final bx = x(b);
  final by = y(b);
  final px = x(p);
  final py = y(p);

  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-6) {
    return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  }
  var t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx;
  final cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}
