import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' hide Position;

import 'package:jippy_mobile/services/location_service.dart';

/// Google Maps–style user location colors.
abstract final class GoogleMapsUserLocationStyle {
  static const Color dotColor = Color(0xFF1A73E8);
  static const Color dotBorder = Colors.white;
  static const double dotSize = 18;
  static const double dotBorderWidth = 3;

  static const Color accuracyFill = Color(0x261A73E8);
  static const Color accuracyStroke = Color(0x4D1A73E8);

  static const double beamSize = 56;
}

const Duration _headingMinInterval = Duration(milliseconds: 250);
const double _headingMinDeltaDegrees = 10;

/// Self-contained user location overlay. Subscribes to [LocationService] internally
/// so parent screens are not rebuilt on every compass tick.
class MapUserLocationLayer extends StatefulWidget {
  const MapUserLocationLayer({super.key});

  @override
  State<MapUserLocationLayer> createState() => _MapUserLocationLayerState();
}

class _MapUserLocationLayerState extends State<MapUserLocationLayer> {
  final LocationService _locationService = LocationService.instance;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<double?>? _headingSub;

  LatLng? _position;
  double? _accuracyMeters;
  double? _compassHeading;
  double? _gpsHeading;
  double? _displayHeading;

  double? _lastPaintedHeading;
  DateTime? _lastHeadingPaintTime;

  static const _dotMarkerSize = Size(
    GoogleMapsUserLocationStyle.dotSize +
        GoogleMapsUserLocationStyle.dotBorderWidth * 2,
    GoogleMapsUserLocationStyle.dotSize +
        GoogleMapsUserLocationStyle.dotBorderWidth * 2,
  );

  static const _beamMarkerSize = Size(
    GoogleMapsUserLocationStyle.beamSize,
    GoogleMapsUserLocationStyle.beamSize,
  );

  @override
  void initState() {
    super.initState();
    _primeFromCache();
    _positionSub = _locationService.stream.listen(_onPosition);
    _headingSub = _locationService.headingStream.listen(_onCompassHeading);
  }

  void _primeFromCache() {
    final cached = _locationService.lastKnown;
    if (cached == null) return;
    _position = LatLng(cached.latitude, cached.longitude);
    _accuracyMeters = cached.accuracy;
    _gpsHeading = _validHeading(cached.heading);
    _displayHeading = resolveUserMapHeading(
      compassHeading: _compassHeading,
      gpsHeading: _gpsHeading,
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _headingSub?.cancel();
    super.dispose();
  }

  double? _validHeading(double? heading) {
    if (heading == null || heading.isNaN || !heading.isFinite || heading < 0) {
      return null;
    }
    return heading;
  }

  void _onPosition(Position position) {
    final next = LatLng(position.latitude, position.longitude);
    final nextAccuracy = position.accuracy;
    final nextGpsHeading = _validHeading(position.heading);

    final positionUnchanged =
        _position?.latitude == next.latitude &&
        _position?.longitude == next.longitude &&
        _accuracyMeters == nextAccuracy &&
        _gpsHeading == nextGpsHeading;

    if (positionUnchanged) return;

    _position = next;
    _accuracyMeters = nextAccuracy;
    _gpsHeading = nextGpsHeading;

    final resolved = resolveUserMapHeading(
      compassHeading: _compassHeading,
      gpsHeading: _gpsHeading,
    );
    if (resolved != _displayHeading) {
      _displayHeading = resolved;
      _lastPaintedHeading = resolved;
      _lastHeadingPaintTime = DateTime.now();
    }

    setState(() {});
  }

  void _onCompassHeading(double? heading) {
    _compassHeading = _validHeading(heading);
    final resolved = resolveUserMapHeading(
      compassHeading: _compassHeading,
      gpsHeading: _gpsHeading,
    );
    if (!_shouldRepaintHeading(resolved)) return;

    setState(() {
      _displayHeading = resolved;
      _lastPaintedHeading = resolved;
      _lastHeadingPaintTime = DateTime.now();
    });
  }

  bool _shouldRepaintHeading(double? next) {
    if (next == _displayHeading) return false;
    if (next == null || _displayHeading == null) return true;

    final now = DateTime.now();
    final lastPaint = _lastHeadingPaintTime;
    if (lastPaint != null && now.difference(lastPaint) < _headingMinInterval) {
      return false;
    }

    final last = _lastPaintedHeading;
    if (last != null) {
      var delta = (next - last).abs() % 360;
      if (delta > 180) delta = 360 - delta;
      if (delta < _headingMinDeltaDegrees) return false;
    }

    return true;
  }

  double? _accuracyDiameterPixels(MapController controller, LatLng position) {
    final accuracy = _accuracyMeters;
    if (accuracy == null ||
        !accuracy.isFinite ||
        accuracy <= 0 ||
        accuracy >= 250) {
      return null;
    }
    final metersPerPixel = controller.getMetersPerPixelAtLatitude(
      position.latitude,
    );
    if (!metersPerPixel.isFinite || metersPerPixel <= 0) return null;
    return (accuracy / metersPerPixel * 2).clamp(16.0, 240.0);
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    if (position == null) return const SizedBox.shrink();

    final controller = MapController.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    final point = Geographic(lon: position.longitude, lat: position.latitude);
    final heading = _displayHeading;
    final showHeading = heading != null;

    final accuracyDiameter = _accuracyDiameterPixels(controller, position);

    final markers = <Marker>[
      if (accuracyDiameter != null)
        Marker(
          point: point,
          size: Size(accuracyDiameter, accuracyDiameter),
          child: const RepaintBoundary(
            child: IgnorePointer(child: _GoogleMapsAccuracyHalo()),
          ),
        ),
      if (showHeading)
        Marker(
          point: point,
          size: _beamMarkerSize,
          rotate: true,
          child: RepaintBoundary(
            child: IgnorePointer(
              child: Transform.rotate(
                angle: heading * math.pi / 180,
                child: const CustomPaint(
                  size: _beamMarkerSize,
                  painter: _GoogleMapsHeadingBeamPainter(),
                ),
              ),
            ),
          ),
        ),
      Marker(
        point: point,
        size: _dotMarkerSize,
        rotate: true,
        child: const RepaintBoundary(
          child: IgnorePointer(child: _GoogleMapsUserDot()),
        ),
      ),
    ];

    return WidgetLayer(markers: markers);
  }
}

class _GoogleMapsAccuracyHalo extends StatelessWidget {
  const _GoogleMapsAccuracyHalo();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: GoogleMapsUserLocationStyle.accuracyFill,
        border: Border.all(
          color: GoogleMapsUserLocationStyle.accuracyStroke,
          width: 1,
        ),
      ),
    );
  }
}

class _GoogleMapsUserDot extends StatelessWidget {
  const _GoogleMapsUserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: GoogleMapsUserLocationStyle.dotSize,
      height: GoogleMapsUserLocationStyle.dotSize,
      decoration: BoxDecoration(
        color: GoogleMapsUserLocationStyle.dotColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: GoogleMapsUserLocationStyle.dotBorder,
          width: GoogleMapsUserLocationStyle.dotBorderWidth,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// Light blue directional wedge (Google Maps–style bearing indicator).
class _GoogleMapsHeadingBeamPainter extends CustomPainter {
  const _GoogleMapsHeadingBeamPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const sweep = math.pi / 3.2;
    final start = -math.pi / 2 - sweep / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        const [
          Color(0x661A73E8),
          Color(0x141A73E8),
        ],
        const [0.0, 1.0],
      );

    final path = ui.Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(rect, start, sweep, false)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GoogleMapsHeadingBeamPainter oldDelegate) =>
      false;
}

/// Prefers compass bearing; falls back to GPS course when valid.
double? resolveUserMapHeading({
  double? compassHeading,
  double? gpsHeading,
}) {
  if (compassHeading != null &&
      !compassHeading.isNaN &&
      compassHeading.isFinite &&
      compassHeading >= 0) {
    return compassHeading;
  }
  if (gpsHeading != null &&
      !gpsHeading.isNaN &&
      gpsHeading.isFinite &&
      gpsHeading >= 0) {
    return gpsHeading;
  }
  return null;
}
