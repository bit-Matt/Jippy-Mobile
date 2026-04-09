import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jippy_mobile/utils/route_polyline_hit.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('metersPerPixelAtLatitude', () {
    test('equator zoom 0 matches Web Mercator constant', () {
      final mpp = metersPerPixelAtLatitude(0, 0);
      expect(mpp, closeTo(156543.03392, 0.001));
    });

    test('halves when zoom increases by one at equator', () {
      final z0 = metersPerPixelAtLatitude(0, 0);
      final z1 = metersPerPixelAtLatitude(0, 1);
      expect(z1, closeTo(z0 / 2, z0 * 1e-9));
    });

    test('Iloilo-scale zoom 14 is single-digit to tens of meters per pixel', () {
      const iloiloLat = 10.7202;
      final mpp = metersPerPixelAtLatitude(iloiloLat, 14);
      final cosLat = math.cos(iloiloLat * math.pi / 180.0);
      final expected = 156543.03392 * cosLat / math.pow(2, 14);
      expect(mpp, closeTo(expected, 1e-6));
      expect(mpp, greaterThan(5));
      expect(mpp, lessThan(50));
    });
  });

  group('minDistanceMetersPointToPolyline', () {
    test('point on segment returns small distance', () {
      final a = LatLng(10.0, 122.0);
      final b = LatLng(10.002, 122.0);
      final mid = LatLng(10.001, 122.0);
      final d = minDistanceMetersPointToPolyline(mid, [a, b]);
      expect(d, lessThan(5.0));
    });

    test('point far from segment exceeds threshold', () {
      final a = LatLng(10.0, 122.0);
      final b = LatLng(10.002, 122.0);
      final far = LatLng(10.5, 122.0);
      final d = minDistanceMetersPointToPolyline(far, [a, b]);
      expect(d, greaterThan(1000.0));
    });

    test('short polyline returns infinity', () {
      final d = minDistanceMetersPointToPolyline(LatLng(10, 122), [
        LatLng(10, 122),
      ]);
      expect(d, double.infinity);
    });
  });

  group('routeIdsNearPolylines', () {
    test('deduplicates same route id across two directions', () {
      final polylines = [
        RouteHitPolyline(
          routeId: 'r1',
          points: [LatLng(10.0, 122.0), LatLng(10.01, 122.0)],
        ),
        RouteHitPolyline(
          routeId: 'r1',
          points: [LatLng(10.02, 122.0), LatLng(10.03, 122.0)],
        ),
      ];
      final tap = LatLng(10.005, 122.0);
      final ids = routeIdsNearPolylines(tap, polylines, 500);
      expect(ids, equals({'r1'}));
    });

    test('returns distinct route ids when both are near', () {
      final polylines = [
        RouteHitPolyline(
          routeId: 'a',
          points: [LatLng(10.0, 122.0), LatLng(10.002, 122.0)],
        ),
        RouteHitPolyline(
          routeId: 'b',
          points: [LatLng(10.0, 122.01), LatLng(10.002, 122.01)],
        ),
      ];
      final tap = LatLng(10.001, 122.005);
      final ids = routeIdsNearPolylines(tap, polylines, 800);
      expect(ids.contains('a'), isTrue);
      expect(ids.contains('b'), isTrue);
    });
  });
}
