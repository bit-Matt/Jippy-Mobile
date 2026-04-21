import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:jippy_mobile/data/navigate_client.dart';
import 'package:jippy_mobile/models/navigate_suggestion.dart';

void main() {
  group('NavigateClient', () {
    test(
      'fetchNavigationSuggestions posts payload and parses suggestions',
      () async {
        final client = MockClient((request) async {
          expect(request.method, 'POST');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['start'], equals(<double>[10.7, 122.5]));
          expect(payload['end'], equals(<double>[10.75, 122.57]));

          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'suggestions': [
                  {
                    'label': 'fastest',
                    'route': {
                      'legs': [
                        {
                          'type': 'WALK',
                          'route_name': 'Walk Segment',
                          'polyline': 'abc123',
                          'color': null,
                          'distance': 300,
                          'duration': 5,
                          'instructions': [
                            {
                              'text': 'Depart from start',
                              'maneuver_type': 'depart',
                            },
                            {
                              'text': 'Arrive at destination',
                              'maneuver_type': 'arrive',
                            },
                          ],
                          'bbox': [
                            [10.7, 122.5],
                            [10.75, 122.57],
                          ],
                        },
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        });

        final suggestions = await fetchNavigationSuggestions(
          start: const LatLng(10.7, 122.5),
          end: const LatLng(10.75, 122.57),
          client: client,
        );

        expect(suggestions, hasLength(1));
        expect(suggestions.first.label, NavigateSuggestionLabel.fastest);
        expect(suggestions.first.route.legs, hasLength(1));
      },
    );

    test('throws NavigateRequestException for non-2xx response', () async {
      final client = MockClient((_) async {
        return http.Response(jsonEncode({'message': 'bad request'}), 400);
      });

      expect(
        () => fetchNavigationSuggestions(
          start: const LatLng(10.7, 122.5),
          end: const LatLng(10.75, 122.57),
          client: client,
        ),
        throwsA(
          isA<NavigateRequestException>().having(
            (e) => e.message,
            'message',
            contains('bad request'),
          ),
        ),
      );
    });

    test('throws timeout-specific exception message', () async {
      final client = MockClient(
        (_) => Future<http.Response>.error(TimeoutException('timed out')),
      );

      expect(
        () => fetchNavigationSuggestions(
          start: const LatLng(10.7, 122.5),
          end: const LatLng(10.75, 122.57),
          client: client,
        ),
        throwsA(
          isA<NavigateRequestException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('throws when payload is not a valid map', () async {
      final client = MockClient((_) async => http.Response('[]', 200));

      expect(
        () => fetchNavigationSuggestions(
          start: const LatLng(10.7, 122.5),
          end: const LatLng(10.75, 122.57),
          client: client,
        ),
        throwsA(isA<NavigateRequestException>()),
      );
    });

    test('throws when API ok is false', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'ok': false,
            'message': 'navigation unavailable',
            'data': {'suggestions': []},
          }),
          200,
        );
      });

      expect(
        () => fetchNavigationSuggestions(
          start: const LatLng(10.7, 122.5),
          end: const LatLng(10.75, 122.57),
          client: client,
        ),
        throwsA(
          isA<NavigateRequestException>().having(
            (e) => e.message,
            'message',
            contains('navigation unavailable'),
          ),
        ),
      );
    });
  });
}
