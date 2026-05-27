import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:jippy_mobile/models/navigate_suggestion.dart';
import 'package:jippy_mobile/services/navigation_tracker.dart';
import 'package:jippy_mobile/utils/polyline_1e6.dart';

class TripSimulatorState {
  const TripSimulatorState({
    required this.isPlaying,
    required this.speedMultiplier,
    required this.currentPointIndex,
    required this.totalPoints,
  });

  static const TripSimulatorState idle = TripSimulatorState(
    isPlaying: false,
    speedMultiplier: 1,
    currentPointIndex: 0,
    totalPoints: 0,
  );

  final bool isPlaying;
  final double speedMultiplier;
  final int currentPointIndex;
  final int totalPoints;

  bool get hasRoutePoints => totalPoints > 0;
  bool get isComplete =>
      totalPoints > 0 && currentPointIndex >= totalPoints - 1;
}

class TripSimulatorService {
  TripSimulatorService({
    required List<LatLng> routePoints,
    this.baseTick = const Duration(milliseconds: 900),
  }) : _routePoints = List<LatLng>.unmodifiable(routePoints);

  factory TripSimulatorService.fromSuggestion({
    required NavigateSuggestion suggestion,
    Duration baseTick = const Duration(milliseconds: 900),
  }) {
    return TripSimulatorService(
      routePoints: buildRoutePoints(suggestion),
      baseTick: baseTick,
    );
  }

  final Duration baseTick;
  final List<LatLng> _routePoints;

  final StreamController<Position> _positions =
      StreamController<Position>.broadcast();
  final StreamController<TripSimulatorState> _state =
      StreamController<TripSimulatorState>.broadcast();

  Timer? _timer;
  double _speedMultiplier = 1;
  int _currentPointIndex = 0;

  Stream<Position> get positions => _positions.stream;
  Stream<TripSimulatorState> get stateStream => _state.stream;

  List<LatLng> get routePoints => _routePoints;
  bool get isPlaying => _timer != null;
  double get speedMultiplier => _speedMultiplier;
  int get currentPointIndex => _currentPointIndex;
  int get totalPoints => _routePoints.length;

  TripSimulatorState get snapshot => TripSimulatorState(
    isPlaying: isPlaying,
    speedMultiplier: _speedMultiplier,
    currentPointIndex: _currentPointIndex,
    totalPoints: totalPoints,
  );

  void initialize() {
    _emitState();
    if (_routePoints.isNotEmpty) {
      _emitPosition(_routePoints[_currentPointIndex], speedMps: 0);
    }
  }

  void play() {
    if (_routePoints.length <= 1) return;
    if (isPlaying) return;
    _startTimer();
    _emitState();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    _emitState();
  }

  void stop() {
    pause();
    _currentPointIndex = 0;
    if (_routePoints.isNotEmpty) {
      _emitPosition(_routePoints.first, speedMps: 0);
    }
    _emitState();
  }

  void setSpeedMultiplier(double value) {
    if (value <= 0) return;
    _speedMultiplier = value;
    if (isPlaying) {
      _timer?.cancel();
      _startTimer();
    }
    _emitState();
  }

  void stepForward({int steps = 1}) {
    if (_routePoints.isEmpty) return;
    if (steps <= 0) return;
    pause();
    _advanceBy(steps);
  }

  void jumpToIndex(int index) {
    if (_routePoints.isEmpty) return;
    final clamped = index.clamp(0, _routePoints.length - 1);
    _currentPointIndex = clamped;
    _emitPosition(_routePoints[_currentPointIndex], speedMps: 0);
    _emitState();
  }

  void jumpNearStop(TripStop stop) {
    if (_routePoints.isEmpty) return;
    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    const distance = Distance();
    for (var i = 0; i < _routePoints.length; i++) {
      final meters = distance.as(LengthUnit.Meter, _routePoints[i], stop.point);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = i;
      }
    }
    jumpToIndex(nearestIndex);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _positions.close();
    await _state.close();
  }

  void _startTimer() {
    final tick = _effectiveTickDuration();
    _timer = Timer.periodic(tick, (_) {
      _advanceBy(1);
      if (_currentPointIndex >= _routePoints.length - 1) {
        pause();
      }
    });
  }

  void _advanceBy(int steps) {
    if (_routePoints.isEmpty) return;

    final previousIndex = _currentPointIndex;
    final next = (_currentPointIndex + steps).clamp(0, _routePoints.length - 1);
    _currentPointIndex = next;

    final point = _routePoints[_currentPointIndex];
    final previous = _routePoints[previousIndex];
    final speed = _estimateSpeedMetersPerSecond(previous, point);
    _emitPosition(point, speedMps: speed);
    _emitState();
  }

  Duration _effectiveTickDuration() {
    final ms = (baseTick.inMilliseconds / _speedMultiplier).round();
    // Keep timer practical under high multipliers.
    return Duration(milliseconds: ms.clamp(80, 2000));
  }

  void _emitPosition(LatLng point, {required double speedMps}) {
    final heading = _headingForCurrentPoint();
    _positions.add(
      Position(
        longitude: point.longitude,
        latitude: point.latitude,
        timestamp: DateTime.now(),
        accuracy: 4,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: heading,
        headingAccuracy: 12,
        speed: speedMps,
        speedAccuracy: 0.6,
        isMocked: true,
      ),
    );
  }

  double _estimateSpeedMetersPerSecond(LatLng previous, LatLng next) {
    if (previous == next) return 0;
    const distance = Distance();
    final meters = distance.as(LengthUnit.Meter, previous, next);
    final seconds = _effectiveTickDuration().inMilliseconds / 1000;
    if (seconds <= 0) return 0;
    return meters / seconds;
  }

  double _headingForCurrentPoint() {
    if (_routePoints.length <= 1) return 0;
    final curr = _routePoints[_currentPointIndex];
    final nextIndex = (_currentPointIndex + 1).clamp(
      0,
      _routePoints.length - 1,
    );
    final next = _routePoints[nextIndex];
    return _bearingDegrees(curr, next);
  }

  void _emitState() {
    _state.add(snapshot);
  }

  static List<LatLng> buildRoutePoints(NavigateSuggestion suggestion) {
    final points = <LatLng>[];
    for (final leg in suggestion.route.legs) {
      final encoded = leg.polyline.trim();
      if (encoded.isEmpty) continue;
      final decoded = decodeApiRoutePolyline(encoded);
      if (decoded == null || decoded.isEmpty) continue;

      for (final point in decoded) {
        if (points.isEmpty) {
          points.add(point);
          continue;
        }
        final previous = points.last;
        const distance = Distance();
        final meters = distance.as(LengthUnit.Meter, previous, point);
        if (meters < 1.2) continue;
        points.add(point);
      }
    }
    return points;
  }

  static double _bearingDegrees(LatLng start, LatLng end) {
    final lat1 = _toRadians(start.latitude);
    final lat2 = _toRadians(end.latitude);
    final deltaLng = _toRadians(end.longitude - start.longitude);
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    final theta = math.atan2(y, x);
    final degrees = _toDegrees(theta);
    return (degrees + 360) % 360;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
  static double _toDegrees(double radians) => radians * 180 / math.pi;
}
