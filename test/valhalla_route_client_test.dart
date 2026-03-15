import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polyline_codec/polyline_codec.dart';

import 'package:jippy_mobile/data/valhalla_route_client.dart';
import 'package:jippy_mobile/models/route_point.dart';

void main() {
  group('ValhallaRouteClient', () {
    test('fetchRoadAlignedRoute throws when waypoints length < 2', () async {
      final client = MockClient((_) async => http.Response('', 200));
      expect(
        () => fetchRoadAlignedRoute([const RoutePoint(id: '1', sequence: 0, address: '', lat: 0, lon: 0)], client: client),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fetchRoadAlignedRoute parses response and decodes polyline', () async {
      // Encode two points so we get a valid shape string.
      const points = [
        [10.72, 122.56],
        [10.73, 122.57],
      ];
      final shape = PolylineCodec.encode(points, precision: 5);
      final body = jsonEncode({
        'trip': {
          'legs': [
            {'shape': shape},
          ],
        },
      });
      final client = MockClient((_) async => http.Response(body, 200));

      final waypoints = [
        const RoutePoint(id: 'a', sequence: 0, address: '', lat: 10.72, lon: 122.56),
        const RoutePoint(id: 'b', sequence: 1, address: '', lat: 10.73, lon: 122.57),
      ];

      final result = await fetchRoadAlignedRoute(waypoints, client: client);

      expect(result.length, 2);
      expect(result[0].latitude, closeTo(10.72, 1e-5));
      expect(result[0].longitude, closeTo(122.56, 1e-5));
      expect(result[1].latitude, closeTo(10.73, 1e-5));
      expect(result[1].longitude, closeTo(122.57, 1e-5));
    });

    test('fetchRoadAlignedRoute throws ValhallaRouteException on 4xx', () async {
      final client = MockClient((_) async => http.Response('{"error": "Not found"}', 404));
      final waypoints = [
        const RoutePoint(id: 'a', sequence: 0, address: '', lat: 10.72, lon: 122.56),
        const RoutePoint(id: 'b', sequence: 1, address: '', lat: 10.73, lon: 122.57),
      ];

      expect(
        () => fetchRoadAlignedRoute(waypoints, client: client),
        throwsA(isA<ValhallaRouteException>()),
      );
    });

    test('fetchRoadAlignedRoute throws when trip.legs is empty', () async {
      final body = jsonEncode({'trip': {'legs': []}});
      final client = MockClient((_) async => http.Response(body, 200));
      final waypoints = [
        const RoutePoint(id: 'a', sequence: 0, address: '', lat: 10.72, lon: 122.56),
        const RoutePoint(id: 'b', sequence: 1, address: '', lat: 10.73, lon: 122.57),
      ];

      expect(
        () => fetchRoadAlignedRoute(waypoints, client: client),
        throwsA(isA<ValhallaRouteException>()),
      );
    });

    test('checkValhallaStatus returns true when status is 200', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final result = await checkValhallaStatus(client: client);
      expect(result, isTrue);
    });

    test('checkValhallaStatus returns false when status is 503', () async {
      final client = MockClient((_) async => http.Response('', 503));
      final result = await checkValhallaStatus(client: client);
      expect(result, isFalse);
    });
  });
}
