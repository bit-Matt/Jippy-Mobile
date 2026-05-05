import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Shared location stream for screens that need live GPS updates.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  static const int _distanceFilterMeters = 8;

  StreamController<Position>? _controller;
  StreamSubscription<Position>? _geoSub;
  Position? _lastKnown;
  LocationPermission? _lastPermission;

  Position? get lastKnown => _lastKnown;
  LocationPermission? get lastPermission => _lastPermission;

  Stream<Position> get stream {
    _controller ??= StreamController<Position>.broadcast(
      onListen: _startStream,
      onCancel: _stopStreamIfIdle,
    );
    return _controller!.stream;
  }

  Future<bool> isServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    _lastPermission = permission;
    return permission;
  }

  void _startStream() {
    if (_geoSub != null) return;
    _geoSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: _distanceFilterMeters,
      ),
    ).listen(
      (Position pos) {
        _lastKnown = pos;
        _controller?.add(pos);
      },
      onError: (Object error, StackTrace stackTrace) {
        _controller?.addError(error, stackTrace);
      },
    );
  }

  void _stopStreamIfIdle() {
    if (_controller?.hasListener == true) return;
    _geoSub?.cancel();
    _geoSub = null;
    _controller?.close();
    _controller = null;
  }
}
