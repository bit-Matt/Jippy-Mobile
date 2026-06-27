import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' show Geographic, LineString, LngLatBounds, Polygon, Position;

Geographic toGeographic(LatLng point) =>
    Geographic(lon: point.longitude, lat: point.latitude);

LatLng toLatLng(Geographic point) => LatLng(point.lat, point.lon);

LineString toLineString(List<LatLng> points) =>
    LineString.from(points.map(toGeographic));

Polygon toPolygon(List<LatLng> ring) {
  if (ring.isEmpty) {
    return Polygon.from(const <Iterable<Position>>[]);
  }
  final closed = List<LatLng>.from(ring);
  if (closed.first != closed.last) {
    closed.add(closed.first);
  }
  return Polygon.from([closed.map(toGeographic)]);
}

LngLatBounds toLngLatBounds(List<LatLng> points) =>
    LngLatBounds.fromPoints(points.map(toGeographic).toList(growable: false));
