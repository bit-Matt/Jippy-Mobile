import 'package:flutter_test/flutter_test.dart';

import 'package:jippy_mobile/models/navigate_suggestion.dart';

NavigateSuggestion _suggestion({
  required String label,
  required List<Map<String, dynamic>> legs,
}) {
  return NavigateSuggestion.fromJson({
    'label': label,
    'route': {'legs': legs},
  })!;
}

Map<String, dynamic> _walkLeg({double duration = 240}) => {
      'type': 'WALK',
      'route_name': 'Walk',
      'polyline': 'a',
      'distance': 200,
      'duration': duration,
      'instructions': [
        {'text': 'Depart', 'maneuver_type': 'depart'},
      ],
      'bbox': [],
    };

Map<String, dynamic> _jeepneyLeg({double duration = 720}) => {
      'type': 'JEEPNEY',
      'route_name': 'Jeep Segment',
      'polyline': 'b',
      'distance': 1500,
      'duration': duration,
      'instructions': [
        {'text': 'Board jeep', 'maneuver_type': 'board'},
        {'text': 'Alight jeep', 'maneuver_type': 'alight'},
      ],
      'bbox': [],
    };

Map<String, dynamic> _tricycleLeg({double duration = 600}) => {
      'type': 'TRICYCLE',
      'route_name': 'Tricycle Segment',
      'polyline': 'c',
      'distance': 900,
      'duration': duration,
      'instructions': [
        {'text': 'Board tricycle', 'maneuver_type': 'board'},
        {'text': 'Arrive', 'maneuver_type': 'arrive'},
      ],
      'bbox': [],
    };

void main() {
  group('NavigateSuggestion ride counts', () {
    test('transitRideCount counts jeepney and tricycle, not walk', () {
      final suggestion = _suggestion(
        label: 'simplest',
        legs: [_walkLeg(), _jeepneyLeg(), _tricycleLeg()],
      );

      expect(suggestion.jeepneyRideCount, 1);
      expect(suggestion.tricycleRideCount, 1);
      expect(suggestion.jeepneyTransferCount, 0);
      expect(suggestion.transitRideCount, 2);
      expect(suggestion.hasTricycleLeg, isTrue);
      expect(suggestion.transitRideSummary, '1 Ride + 1 Tricycle');
    });

    test('tricycle-only route has one transit ride and zero jeepney transfers', () {
      final suggestion = _suggestion(
        label: 'fastest',
        legs: [_walkLeg(), _tricycleLeg()],
      );

      expect(suggestion.transitRideCount, 1);
      expect(suggestion.tricycleRideCount, 1);
      expect(suggestion.jeepneyTransferCount, 0);
      expect(suggestion.hasTricycleLeg, isTrue);
      expect(suggestion.transitRideSummary, '1 Tricycle Ride');
    });

    test('jeepney-only route uses Ride label', () {
      final suggestion = _suggestion(
        label: 'fastest',
        legs: [_walkLeg(), _jeepneyLeg()],
      );

      expect(suggestion.transitRideSummary, '1 Ride');
    });

    test('multiple jeepneys and tricycles use plural labels', () {
      final suggestion = _suggestion(
        label: 'fastest',
        legs: [
          _walkLeg(),
          _jeepneyLeg(),
          _jeepneyLeg(duration: 480),
          _tricycleLeg(),
        ],
      );

      expect(suggestion.transitRideSummary, '2 Rides + 1 Tricycle');
    });

    test('two jeepney legs yield one jeepney transfer', () {
      final suggestion = _suggestion(
        label: 'fastest',
        legs: [_walkLeg(), _jeepneyLeg(), _jeepneyLeg(duration: 480)],
      );

      expect(suggestion.jeepneyRideCount, 2);
      expect(suggestion.jeepneyTransferCount, 1);
      expect(suggestion.hasTricycleLeg, isFalse);
    });
  });

  group('compareNavigateSuggestions', () {
    test('sorts by fewest jeepney transfers first', () {
      final oneJeepney = _suggestion(
        label: 'a',
        legs: [_walkLeg(), _jeepneyLeg()],
      );
      final twoJeepneys = _suggestion(
        label: 'b',
        legs: [_walkLeg(), _jeepneyLeg(), _jeepneyLeg(duration: 480)],
      );

      expect(compareNavigateSuggestions(oneJeepney, twoJeepneys), lessThan(0));
      expect(compareNavigateSuggestions(twoJeepneys, oneJeepney), greaterThan(0));
    });

    test('deprioritizes tricycle routes with equal jeepney transfers', () {
      final jeepneyOnly = _suggestion(
        label: 'a',
        legs: [_walkLeg(), _jeepneyLeg()],
      );
      final tricycleOnly = _suggestion(
        label: 'b',
        legs: [_walkLeg(), _tricycleLeg()],
      );

      expect(compareNavigateSuggestions(jeepneyOnly, tricycleOnly), lessThan(0));
      expect(compareNavigateSuggestions(tricycleOnly, jeepneyOnly), greaterThan(0));
    });

    test('uses total transit rides as tertiary sort key', () {
      final jeepneyAndTricycle = _suggestion(
        label: 'a',
        legs: [_walkLeg(), _jeepneyLeg(), _tricycleLeg()],
      );
      final tricycleOnly = _suggestion(
        label: 'b',
        legs: [_walkLeg(), _tricycleLeg()],
      );

      expect(
        compareNavigateSuggestions(jeepneyAndTricycle, tricycleOnly),
        greaterThan(0),
      );
    });

    test('uses duration as final tiebreaker', () {
      final faster = _suggestion(
        label: 'a',
        legs: [_walkLeg(), _jeepneyLeg(duration: 600)],
      );
      final slower = _suggestion(
        label: 'b',
        legs: [_walkLeg(), _jeepneyLeg(duration: 900)],
      );

      expect(compareNavigateSuggestions(faster, slower), lessThan(0));
    });

    test('sort keeps all suggestions without dropping any', () {
      final suggestions = [
        _suggestion(label: 'two_jeep', legs: [_walkLeg(), _jeepneyLeg(), _jeepneyLeg()]),
        _suggestion(label: 'tri_only', legs: [_walkLeg(), _tricycleLeg()]),
        _suggestion(label: 'one_jeep', legs: [_walkLeg(), _jeepneyLeg()]),
        _suggestion(label: 'jeep_tri', legs: [_walkLeg(), _jeepneyLeg(), _tricycleLeg()]),
      ];

      final sorted = List<NavigateSuggestion>.from(suggestions)
        ..sort(compareNavigateSuggestions);

      expect(sorted, hasLength(4));
      expect(sorted[0].rawLabel, 'one_jeep');
      expect(sorted[1].rawLabel, 'tri_only');
      expect(sorted[2].rawLabel, 'jeep_tri');
      expect(sorted[3].rawLabel, 'two_jeep');
    });
  });
}
