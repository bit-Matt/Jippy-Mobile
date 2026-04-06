import 'package:flutter_test/flutter_test.dart';
import 'package:jippy_mobile/models/routes_and_stations_data.dart';

void main() {
  group('Road closures parsing', () {
    test('parses closures and sorts points by sequence', () {
      final payload = <String, dynamic>{
        'ok': true,
        'data': {
          'routes': [],
          'regions': [],
          'closures': [
            {
              'id': 'closure-1',
              'closureName': 'Downtown Reroute',
              'closureDescription': 'Roadworks',
              'points': [
                {
                  'id': 'p3',
                  'sequence': 3,
                  'point': [10.7308, 122.5592],
                },
                {
                  'id': 'p1',
                  'sequence': 1,
                  'point': [10.7307, 122.5578],
                },
                {
                  'id': 'p2',
                  'sequence': 2,
                  'point': [10.7315, 122.5584],
                },
              ],
            },
          ],
        },
      };

      final data = RoutesAndStationsData.fromJson(payload);
      expect(data.closures, hasLength(1));

      final closure = data.closures.first;
      expect(closure.canRenderPolygon, isTrue);

      final orderedIds = closure.orderedPoints.map((p) => p.id).toList();
      expect(orderedIds, equals(['p1', 'p2', 'p3']));
    });

    test('skips malformed closure item safely', () {
      final payload = <String, dynamic>{
        'ok': true,
        'data': {
          'routes': [],
          'regions': [],
          'closures': [
            {
              'id': 'closure-valid',
              'closureName': 'Valid',
              'closureDescription': 'ok',
              'points': [
                {
                  'id': 'a',
                  'sequence': 1,
                  'point': [10.1, 122.1],
                },
                {
                  'id': 'b',
                  'sequence': 2,
                  'point': [10.2, 122.2],
                },
                {
                  'id': 'c',
                  'sequence': 3,
                  'point': [10.3, 122.3],
                },
              ],
            },
            {
              'id': 'closure-invalid',
              'closureName': 'Invalid tuple',
              'closureDescription': 'bad',
              'points': [
                {
                  'id': 'x1',
                  'sequence': 1,
                  'point': [10.0], // invalid tuple
                },
              ],
            },
          ],
        },
      };

      final data = RoutesAndStationsData.fromJson(payload);
      expect(data.closures, hasLength(1));
      expect(data.closures.first.id, 'closure-valid');
    });

    test('closure with fewer than 3 points is non-renderable', () {
      final payload = <String, dynamic>{
        'ok': true,
        'data': {
          'routes': [],
          'regions': [],
          'closures': [
            {
              'id': 'closure-2pts',
              'closureName': 'Too few points',
              'closureDescription': 'skip when rendering',
              'points': [
                {
                  'id': 'p1',
                  'sequence': 1,
                  'point': [10.0, 122.0],
                },
                {
                  'id': 'p2',
                  'sequence': 2,
                  'point': [10.1, 122.1],
                },
              ],
            },
          ],
        },
      };

      final data = RoutesAndStationsData.fromJson(payload);
      expect(data.closures, hasLength(1));
      expect(data.closures.first.canRenderPolygon, isFalse);
    });
  });
}
