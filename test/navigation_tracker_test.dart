import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jippy_mobile/models/navigate_suggestion.dart';
import 'package:jippy_mobile/services/navigation_tracker.dart';
import 'package:jippy_mobile/utils/polyline_1e6.dart';

void main() {
  const encoded =
      'os`lSmfdyhFda@p[tMhK~XxTzKvItEbDdEfDtJtH~J|HzBjBpH~FtKvIrRxNzE|DvHdGdL~Id@`@zErDjEhDjP|LtQpMsLxOuUb[kJ~IeFjCiE~A{Dt@{Jh@cCBuF@gGIyDFwBzFeDtEmBhA{Dz@kGbAcEp@aThA}BfBy@hB]dDWv]i@zC_BnBsMhDoTtGkLzDsG~B}DnBwK`ImBjDy@dDc@~E]dG}B`J]lAyBfIiEdKuCjD{FdI}AxBo@bAk`@zh@uEjGaLjOwAnBsJbLoEbI}C~H_BvFsC|K{A|H_B~IcAdGoBvPq@~MQlJItHOv_@]jcAExg@AjKQj\\OlWGrb@AdCGp[A`BW|Dg@dDy@|C}BhGwMdZ{ArDM`CExCTfC~@nDpAjEpEtOo@rClRfz@Jx@PvDdAlJd@lCxCbUYl@Kp@?t@Pr@\\l@h@`@p@Tr@Ft@In@Wl@k@`Bg@dBWtAKlCYzb@S~FCxV@jE@jl@VtKPzHx@xw@H~@?`A?|F@vCAvEAtd@NlX?jA?hC{@`EsCjD{BpAcAd@_@xn@_e@pByA`f@u]zCyBpA{@tDoBrf@oVpCqAjAq@hBdAlLzGlwApw@|AX`BAnFg@z@|f@UnGYY_@Sc@Ic@Ac@HUHQJ_@b@Ob@Eh@Bf@Nd@X^f@Xl@Jn@Cj@Sl@lC^bCPhCf@vP';

  NavigateSuggestion buildSuggestion() {
    return NavigateSuggestion(
      rawLabel: 'fastest',
      label: NavigateSuggestionLabel.fastest,
      route: NavigateRoute(
        legs: [
          const NavigateLeg(
            type: NavigateLegType.jeepney,
            routeName: 'Leg 1',
            polyline: encoded,
            colorHex: null,
            distanceMeters: 1000,
            durationMinutes: 10,
            instructions: [],
            bbox: [],
          ),
          const NavigateLeg(
            type: NavigateLegType.walk,
            routeName: 'Leg 2',
            polyline: encoded,
            colorHex: null,
            distanceMeters: 500,
            durationMinutes: 5,
            instructions: [],
            bbox: [],
          ),
        ],
      ),
    );
  }

  test('emits ordered proximity events and marks trip complete', () async {
    final suggestion = buildSuggestion();
    final points = decodeApiRoutePolyline(encoded)!;
    final stopPoint = points.last;

    final controller = StreamController<Position>.broadcast();
    final tracker = NavigationTracker(
      suggestion: suggestion,
      thresholdMeters: 35,
      positionStream: controller.stream,
      lastKnownPosition: () => null,
    );
    final events = <ProximityEvent>[];
    final sub = tracker.events.listen(events.add);

    tracker.start();
    controller.add(_position(stopPoint.latitude, stopPoint.longitude));
    await Future<void>.delayed(Duration.zero);

    controller.add(_position(stopPoint.latitude, stopPoint.longitude));
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events.first.tripComplete, isFalse);
    expect(events.last.tripComplete, isTrue);
    expect(tracker.isComplete, isTrue);

    await sub.cancel();
    await tracker.stop();
    await controller.close();
  });

  test('ignores fixes outside threshold', () async {
    final suggestion = buildSuggestion();
    final points = decodeApiRoutePolyline(encoded)!;
    final stopPoint = points.last;

    final controller = StreamController<Position>.broadcast();
    final tracker = NavigationTracker(
      suggestion: suggestion,
      thresholdMeters: 5,
      positionStream: controller.stream,
      lastKnownPosition: () => null,
    );
    final events = <ProximityEvent>[];
    final sub = tracker.events.listen(events.add);

    tracker.start();
    controller.add(_position(stopPoint.latitude + 0.001, stopPoint.longitude));
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
    expect(tracker.currentStopIndex, 0);

    await sub.cancel();
    await tracker.stop();
    await controller.close();
  });
}

Position _position(double latitude, double longitude) {
  return Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: DateTime.now(),
    accuracy: 4,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    isMocked: true,
  );
}
