import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Shared location stream for screens that need live GPS updates.
///
/// Responsibilities:
/// - Emit high-accuracy [Position] updates (heading, speed, accuracy included).
/// - Broadcast OS location-service on/off state via [serviceStatusStream] so
///   screens can react when the user toggles location while the app is open.
/// - Provide [refresh] for app-resume / manual recovery paths.
class LocationService {
  LocationService._() {
    _initServiceStatusListener();
  }

  static final LocationService instance = LocationService._();

  /// Minimum horizontal movement (meters) between emitted updates. Tuned small
  /// so the blue dot feels responsive while walking, without flooding setState.
  static const int _distanceFilterMeters = 3;

  StreamController<Position>? _controller;
  StreamSubscription<Position>? _geoSub;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  final StreamController<ServiceStatus> _statusController =
      StreamController<ServiceStatus>.broadcast();

  Position? _lastKnown;
  LocationPermission? _lastPermission;
  ServiceStatus? _lastServiceStatus;

  Position? get lastKnown => _lastKnown;
  LocationPermission? get lastPermission => _lastPermission;
  ServiceStatus? get lastServiceStatus => _lastServiceStatus;

  /// Broadcast stream that mirrors [Geolocator.getServiceStatusStream].
  /// Subscribed for the entire app lifetime.
  Stream<ServiceStatus> get serviceStatusStream => _statusController.stream;

  /// Device orientation heading in degrees from compass/magnetometer.
  ///
  /// Unlike [Position.heading], this updates while stationary as the user rotates
  /// the phone, which is ideal for orienting an on-map cone.
  Stream<double?> get headingStream {
    final events = FlutterCompass.events;
    if (events == null) return const Stream<double?>.empty();
    return events.map((event) => event.heading);
  }

  /// Live position stream. Shared across all listeners (multicast).
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

  /// Manual recovery hook. Screens can call this on [AppLifecycleState.resumed]
  /// (or any time they suspect the OS toggled location) to re-check the service
  /// and ensure the position subscription is running.
  ///
  /// Safe to call repeatedly; does nothing harmful if the stream is already up.
  Future<void> refresh() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    _lastServiceStatus = enabled ? ServiceStatus.enabled : ServiceStatus.disabled;

    if (!enabled) return;

    final permission = await Geolocator.checkPermission();
    _lastPermission = permission;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    if (_controller != null && _controller!.hasListener && _geoSub == null) {
      _startStream();
    }

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: _buildLocationSettings(),
      );
      _lastKnown = current;
      _controller?.add(current);
    } catch (_) {
      // Best-effort prime; ignore errors.
    }
  }

  void _initServiceStatusListener() {
    try {
      _serviceStatusSub = Geolocator.getServiceStatusStream().listen(
        (ServiceStatus status) async {
          final previous = _lastServiceStatus;
          _lastServiceStatus = status;
          _statusController.add(status);

          if (status == ServiceStatus.enabled &&
              previous != ServiceStatus.enabled) {
            // The user just turned location ON while the app is open.
            // Make sure permission + position stream are ready.
            await requestPermission();
            if (_controller != null && _controller!.hasListener) {
              _startStream();
              try {
                final current = await Geolocator.getCurrentPosition(
                  locationSettings: _buildLocationSettings(),
                );
                _lastKnown = current;
                _controller?.add(current);
              } catch (_) {}
            }
          } else if (status == ServiceStatus.disabled) {
            await _geoSub?.cancel();
            _geoSub = null;
          }
        },
        onError: (Object _, StackTrace _) {
          // Swallow; status stream is a best-effort signal.
        },
      );
    } catch (_) {
      // Some platforms / test environments may not support this stream.
    }
  }

  LocationSettings _buildLocationSettings() {
    const accuracy = LocationAccuracy.bestForNavigation;
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: accuracy,
        distanceFilter: _distanceFilterMeters,
      );
    }
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: _distanceFilterMeters,
        intervalDuration: const Duration(seconds: 1),
        forceLocationManager: false,
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: _distanceFilterMeters,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return const LocationSettings(
      accuracy: accuracy,
      distanceFilter: _distanceFilterMeters,
    );
  }

  void _startStream() {
    if (_geoSub != null) return;
    _geoSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
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

  /// Dispose resources. Only intended for tests or app shutdown; the singleton
  /// normally lives for the entire app lifetime.
  @visibleForTesting
  Future<void> disposeForTests() async {
    await _geoSub?.cancel();
    await _serviceStatusSub?.cancel();
    await _controller?.close();
    await _statusController.close();
    _geoSub = null;
    _serviceStatusSub = null;
    _controller = null;
  }
}
