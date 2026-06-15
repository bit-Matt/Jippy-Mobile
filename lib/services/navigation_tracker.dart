import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:jippy_mobile/models/navigate_suggestion.dart';
import 'package:jippy_mobile/services/location_service.dart';
import 'package:jippy_mobile/utils/polyline_1e6.dart';

enum TripStopKind { transfer, dropOff }

class TripStop {
  const TripStop({
    required this.point,
    required this.kind,
    required this.label,
    required this.legIndex,
  });

  final LatLng point;
  final TripStopKind kind;
  final String label;
  final int legIndex;
}

class ProximityEvent {
  const ProximityEvent({
    required this.stop,
    required this.distanceMeters,
    required this.tripComplete,
  });

  final TripStop stop;
  final double distanceMeters;
  final bool tripComplete;
}

class NavigationTracker {
  NavigationTracker({
    required this.suggestion,
    this.thresholdMeters = 100,
    LocationService? locationService,
    Stream<Position>? positionStream,
    Position? Function()? lastKnownPosition,
  }) : _locationService = locationService,
       _positionStream = positionStream,
       _lastKnownPosition = lastKnownPosition,
       _stops = _buildStops(suggestion);

  final NavigateSuggestion suggestion;
  final double thresholdMeters;
  final LocationService? _locationService;
  final Stream<Position>? _positionStream;
  final Position? Function()? _lastKnownPosition;
  final List<TripStop> _stops;
  final Distance _distance = const Distance();

  final StreamController<ProximityEvent> _events =
      StreamController<ProximityEvent>.broadcast();
  StreamSubscription<Position>? _positionSub;
  int _nextStopIndex = 0;

  Stream<ProximityEvent> get events => _events.stream;
  int get currentStopIndex => _nextStopIndex;
  List<TripStop> get stops => List<TripStop>.unmodifiable(_stops);
  bool get isComplete => _nextStopIndex >= _stops.length;

  void start() {
    if (_positionSub != null || isComplete) return;
    final streamSource =
        _positionStream ??
        _locationService?.stream ??
        LocationService.instance.stream;
    _positionSub = streamSource.listen(_onPosition);

    Position? known;
    if (_lastKnownPosition != null) {
      known = _lastKnownPosition.call();
    } else if (_locationService != null) {
      known = _locationService.lastKnown;
    } else if (_positionStream == null) {
      known = LocationService.instance.lastKnown;
    }
    if (known != null) {
      _onPosition(known);
    }
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  void _onPosition(Position position) {
    if (_nextStopIndex >= _stops.length) return;

    final stop = _stops[_nextStopIndex];
    final user = LatLng(position.latitude, position.longitude);
    final distanceMeters = _distance.as(LengthUnit.Meter, user, stop.point);
    if (distanceMeters > thresholdMeters) return;

    final isFinal = _nextStopIndex == _stops.length - 1;
    _events.add(
      ProximityEvent(
        stop: stop,
        distanceMeters: distanceMeters,
        tripComplete: isFinal,
      ),
    );
    _nextStopIndex += 1;
  }

  static List<TripStop> _buildStops(NavigateSuggestion suggestion) {
    final legs = suggestion.route.legs;
    if (legs.isEmpty) return const <TripStop>[];

    final stops = <TripStop>[];
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final decoded = decodeApiRoutePolyline(leg.polyline.trim());
      if (decoded == null || decoded.isEmpty) continue;

      final isFinalLeg = i == legs.length - 1;
      if (leg.type == NavigateLegType.walk && !isFinalLeg) continue;

      final kind = isFinalLeg ? TripStopKind.dropOff : TripStopKind.transfer;
      stops.add(
        TripStop(
          point: decoded.last,
          kind: kind,
          label: _labelForStop(legs: legs, stopLegIndex: i, kind: kind),
          legIndex: i,
        ),
      );
    }
    return stops;
  }

  static String _labelForStop({
    required List<NavigateLeg> legs,
    required int stopLegIndex,
    required TripStopKind kind,
  }) {
    if (kind == TripStopKind.dropOff) {
      return 'Destination';
    }
    final nextLeg = stopLegIndex + 1 < legs.length
        ? legs[stopLegIndex + 1]
        : null;
    if (nextLeg == null) return 'Transfer point';

    final routeName = nextLeg.routeName.trim();
    if (routeName.isNotEmpty) {
      return 'Transfer to $routeName';
    }
    return 'Transfer point';
  }
}
