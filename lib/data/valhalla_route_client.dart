import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:polyline_codec/polyline_codec.dart';

import 'map_data_loader.dart';
import '../models/route_point.dart';

/// Timeout for Valhalla API requests.
const Duration _valhallaRouteTimeout = Duration(seconds: 15);
const Duration _valhallaStatusTimeout = Duration(seconds: 5);

/// Checks whether the Valhalla proxy is available.
/// Returns true if GET /api/public/osm/valhalla/status returns 200.
Future<bool> checkValhallaStatus({http.Client? client}) async {
  final uri = Uri.parse('$apiBaseUrl/api/public/osm/valhalla/status');
  try {
    final response = client != null
        ? await client.get(uri).timeout(_valhallaStatusTimeout)
        : await http.get(uri).timeout(_valhallaStatusTimeout);
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Fetches a road-aligned route from the Valhalla proxy (dashboard API).
///
/// Sends [waypoints] (sorted by sequence) to Valhalla and returns decoded
/// polyline points suitable for drawing on the map. Callers should fall back
/// to straight-line segments between waypoints on throw.
///
/// Throws on network error, non-200 response, invalid JSON, empty legs,
/// or missing [trip.legs[].shape]. Pass [client] only for tests.
Future<List<LatLng>> fetchRoadAlignedRoute(
  List<RoutePoint> waypoints, {
  http.Client? client,
}) async {
  if (waypoints.length < 2) {
    throw ArgumentError('At least two waypoints required');
  }

  final sorted = List<RoutePoint>.from(waypoints)
    ..sort((a, b) => a.sequence.compareTo(b.sequence));

  final payload = <String, dynamic>{
    'locations': sorted
        .map((p) => <String, num>{'lat': p.lat, 'lon': p.lon})
        .toList(),
    'costing': 'auto',
    'costing_options': {
      'auto': {'country_crossing_penalty': 2000.0},
    },
    'units': 'kilometers',
  };

  final jsonString = jsonEncode(payload);
  final encoded = Uri.encodeComponent(jsonString);
  final uri = Uri.parse('$apiBaseUrl/api/public/osm/valhalla/route?json=$encoded');

  final response = client != null
      ? await client.get(uri).timeout(_valhallaRouteTimeout)
      : await http.get(uri).timeout(_valhallaRouteTimeout);

  if (response.statusCode != 200) {
    String message = 'Valhalla route API returned ${response.statusCode}';
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final err = body['error'] ?? body['message'] ?? body['error_code'];
        if (err != null) message = err.toString();
      }
    } catch (_) {}
    throw ValhallaRouteException(message);
  }

  final json = jsonDecode(response.body);
  if (json is! Map<String, dynamic>) {
    throw ValhallaRouteException('Valhalla returned invalid JSON');
  }

  final trip = json['trip'];
  if (trip is! Map<String, dynamic>) {
    throw ValhallaRouteException('Valhalla response missing trip');
  }

  final legs = trip['legs'];
  if (legs is! List || legs.isEmpty) {
    throw ValhallaRouteException('Valhalla response has no legs');
  }

  final allPoints = <LatLng>[];
  for (final leg in legs) {
    if (leg is! Map<String, dynamic>) continue;
    final shape = leg['shape'];
    if (shape is! String || shape.isEmpty) {
      throw ValhallaRouteException('Valhalla leg missing shape');
    }
    final decoded = PolylineCodec.decode(shape, precision: 5);
    for (final coord in decoded) {
      if (coord.length >= 2) {
        allPoints.add(LatLng(coord[0].toDouble(), coord[1].toDouble()));
      }
    }
  }

  if (allPoints.isEmpty) {
    throw ValhallaRouteException('Valhalla returned no route points');
  }

  return allPoints;
}

/// Thrown when the Valhalla route API fails or returns unusable data.
/// Callers should fall back to straight-line drawing.
class ValhallaRouteException implements Exception {
  ValhallaRouteException(this.message);
  final String message;
  @override
  String toString() => 'ValhallaRouteException: $message';
}
