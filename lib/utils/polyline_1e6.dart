import 'package:latlong2/latlong.dart';

const double _polyline6Precision = 1_000_000.0;

/// Decodes an encoded polyline where coordinates are stored at [precision].
///
/// This matches the dashboard implementation in `secrets/polylines.ts`.
/// Returns a list of [LatLng] points in degrees.
List<LatLng> decodePolyline(String encoded, {required double precision}) {
  final coordinates = <LatLng>[];
  int index = 0;
  int lat = 0;
  int lon = 0;

  while (index < encoded.length) {
    final latResult = _decodeSingleValue(encoded, index);
    lat += latResult.value;
    index = latResult.nextIndex;

    final lonResult = _decodeSingleValue(encoded, index);
    lon += lonResult.value;
    index = lonResult.nextIndex;

    coordinates.add(
      LatLng(lat / precision, lon / precision),
    );
  }

  return coordinates;
}

/// Decodes a route polyline from the API (polyline6).
///
/// This repo standardizes on **polyline6** (precision 1e6) per
/// `secrets/polyline-encoding-decoding.md`.
///
/// Returns `null` if decoding fails or the result contains out-of-range points.
List<LatLng>? decodeApiRoutePolyline(String encoded) {
  return tryDecodePolyline6(encoded).points;
}

/// Attempts to decode a polyline6 and returns an error reason on failure.
({List<LatLng>? points, String? error}) tryDecodePolyline6(String encoded) {
  if (encoded.trim().isEmpty) {
    return (points: null, error: 'empty');
  }

  try {
    final pts = decodePolyline(encoded, precision: _polyline6Precision);
    if (pts.length < 2) {
      return (points: null, error: 'too_few_points:${pts.length}');
    }

    for (final p in pts) {
      final lat = p.latitude;
      final lon = p.longitude;
      if (!lat.isFinite || !lon.isFinite) {
        return (points: null, error: 'non_finite');
      }
      if (lat < -90 || lat > 90) {
        return (points: null, error: 'lat_out_of_range:$lat');
      }
      if (lon < -180 || lon > 180) {
        return (points: null, error: 'lon_out_of_range:$lon');
      }
    }

    return (points: pts, error: null);
  } catch (e) {
    return (points: null, error: 'exception:${e.runtimeType}');
  }
}

({int value, int nextIndex}) _decodeSingleValue(String encoded, int startIndex) {
  int result = 0;
  int shift = 0;
  int index = startIndex;

  while (true) {
    final byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1f) << shift;
    shift += 5;
    if (byte < 0x20) break;
  }

  final value = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  return (value: value, nextIndex: index);
}

