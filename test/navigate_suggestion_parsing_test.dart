import 'package:flutter_test/flutter_test.dart';

import 'package:jippy_mobile/models/navigate_suggestion.dart';

void main() {
  group('NavigateSuggestion parsing', () {
    test('parses labels, leg types, maneuver types, and bbox', () {
      final parsed = NavigateSuggestionsResponse.fromJson({
        'ok': true,
        'data': {
          'suggestions': [
            {
              'label': 'least_walking',
              'route': {
                'legs': [
                  {
                    'type': 'JEEPNEY',
                    'route_name': 'Route Alpha',
                    'polyline': 'xyz',
                    'color': '#E68C1E',
                    'distance': 1200,
                    'duration': 15,
                    'instructions': [
                      {'text': 'Board route alpha', 'maneuver_type': 'board'},
                      {'text': 'Alight at stop one', 'maneuver_type': 'alight'},
                    ],
                    'bbox': [
                      [10.71, 122.54],
                      [10.72, 122.56],
                    ],
                  },
                ],
              },
            },
          ],
        },
      });

      expect(parsed.ok, isTrue);
      expect(parsed.suggestions, hasLength(1));
      final suggestion = parsed.suggestions.first;
      expect(suggestion.label, NavigateSuggestionLabel.leastWalking);
      expect(suggestion.route.legs.first.type, NavigateLegType.jeepney);
      expect(
        suggestion.route.legs.first.instructions.first.maneuverType,
        NavigateManeuverType.board,
      );
      expect(suggestion.route.legs.first.bbox, hasLength(2));
    });

    test('transferCount uses board instructions first', () {
      final suggestion = NavigateSuggestion.fromJson({
        'label': 'simplest',
        'route': {
          'legs': [
            {
              'type': 'WALK',
              'route_name': 'Walk Segment',
              'polyline': 'a',
              'distance': 200,
              'duration': 4,
              'instructions': [
                {'text': 'Depart', 'maneuver_type': 'depart'},
              ],
              'bbox': [],
            },
            {
              'type': 'JEEPNEY',
              'route_name': 'Jeep Segment',
              'polyline': 'b',
              'distance': 1500,
              'duration': 12,
              'instructions': [
                {'text': 'Board jeep', 'maneuver_type': 'board'},
                {'text': 'Alight jeep', 'maneuver_type': 'alight'},
              ],
              'bbox': [],
            },
            {
              'type': 'TRICYCLE',
              'route_name': 'Tricycle Segment',
              'polyline': 'c',
              'distance': 900,
              'duration': 10,
              'instructions': [
                {'text': 'Board tricycle', 'maneuver_type': 'board'},
                {'text': 'Arrive', 'maneuver_type': 'arrive'},
              ],
              'bbox': [],
            },
          ],
        },
      })!;

      expect(suggestion.boardCount, 2);
      expect(suggestion.transferCount, 1);
      expect(suggestion.totalDistanceMeters, closeTo(2600, 1e-9));
      expect(suggestion.totalDurationMinutes, closeTo(26, 1e-9));
    });

    test('drops malformed suggestions and instructions safely', () {
      final parsed = NavigateSuggestionsResponse.fromJson({
        'ok': true,
        'data': {
          'suggestions': [
            {
              'label': 'fastest',
              'route': {
                'legs': [
                  {
                    'type': 'WALK',
                    'route_name': 'Safe leg',
                    'polyline': '',
                    'distance': '80',
                    'duration': '2',
                    'instructions': [
                      {'text': '', 'maneuver_type': 'turn'},
                      {'text': 'Turn right', 'maneuver_type': 'turn'},
                    ],
                    'bbox': [
                      {'lat': 10.7, 'lng': 122.5},
                      {'latitude': 10.71, 'longitude': 122.51},
                    ],
                  },
                ],
              },
            },
            {'label': 'explorer'},
          ],
        },
      });

      expect(parsed.suggestions, hasLength(1));
      final safe = parsed.suggestions.first.route.legs.first;
      expect(safe.instructions, hasLength(1));
      expect(safe.instructions.first.text, 'Turn right');
      expect(safe.bbox, hasLength(2));
    });
  });
}
