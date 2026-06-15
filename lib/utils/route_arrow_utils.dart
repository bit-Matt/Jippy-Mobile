import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Geographic offset applied to each direction strand (right of travel).
const double routePolylineOffsetMeters = 7.0;

/// Default spacing between direction arrows along a route strand.
const double routeArrowSpacingMeters = 100.0;

const double _arrowSizePx = 14.0;
const Distance _distance = Distance();

/// Shifts [points] perpendicular to travel, [offsetMeters] to the right of
/// each segment bearing.
List<LatLng> offsetPolyline(List<LatLng> points, double offsetMeters) {
  if (points.length < 2 || offsetMeters == 0) return points;

  final shifted = <LatLng>[];
  for (var i = 0; i < points.length; i++) {
    final bearing = _localBearingAt(points, i);
    shifted.add(_destinationPoint(points[i], bearing + 90, offsetMeters));
  }
  return shifted;
}

/// Places chevron markers along [offsetPoints] at [spacingMeters] intervals.
List<Marker> buildArrowMarkers(
  List<LatLng> offsetPoints,
  Color color, {
  double spacingMeters = routeArrowSpacingMeters,
}) {
  if (offsetPoints.length < 2 || spacingMeters <= 0) return const <Marker>[];

  final markers = <Marker>[];
  var nextMarkerAt = spacingMeters;
  var accumulated = 0.0;

  for (var i = 0; i < offsetPoints.length - 1; i++) {
    final start = offsetPoints[i];
    final end = offsetPoints[i + 1];
    final segLen = _distance(start, end);
    if (segLen <= 0) continue;

    final segBearing = _bearingDegrees(start, end);
    final segStartAccumulated = accumulated;
    accumulated += segLen;

    while (nextMarkerAt <= accumulated) {
      final alongSeg = nextMarkerAt - segStartAccumulated;
      final t = (alongSeg / segLen).clamp(0.0, 1.0);
      final point = LatLng(
        start.latitude + (end.latitude - start.latitude) * t,
        start.longitude + (end.longitude - start.longitude) * t,
      );
      markers.add(_arrowMarker(point, segBearing, color));
      nextMarkerAt += spacingMeters;
    }
  }

  return markers;
}

Marker _arrowMarker(LatLng point, double bearingDegrees, Color color) {
  return Marker(
    point: point,
    width: _arrowSizePx,
    height: _arrowSizePx,
    alignment: Alignment.center,
    child: IgnorePointer(
      child: Transform.rotate(
        angle: bearingDegrees * math.pi / 180,
        child: CustomPaint(
          size: const Size(_arrowSizePx, _arrowSizePx),
          painter: _ArrowPainter(color: color),
        ),
      ),
    ),
  );
}

double _localBearingAt(List<LatLng> points, int index) {
  if (points.length < 2) return 0;
  if (index == 0) {
    return _bearingDegrees(points[0], points[1]);
  }
  if (index == points.length - 1) {
    return _bearingDegrees(points[index - 1], points[index]);
  }
  final incoming = _bearingDegrees(points[index - 1], points[index]);
  final outgoing = _bearingDegrees(points[index], points[index + 1]);
  return _averageBearing(incoming, outgoing);
}

double _averageBearing(double a, double b) {
  final aRad = a * math.pi / 180;
  final bRad = b * math.pi / 180;
  final x = math.cos(aRad) + math.cos(bRad);
  final y = math.sin(aRad) + math.sin(bRad);
  final avg = math.atan2(y, x) * 180 / math.pi;
  return (avg + 360) % 360;
}

double _bearingDegrees(LatLng start, LatLng end) {
  final lat1 = _toRadians(start.latitude);
  final lat2 = _toRadians(end.latitude);
  final deltaLng = _toRadians(end.longitude - start.longitude);
  final y = math.sin(deltaLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
  final theta = math.atan2(y, x);
  return (_toDegrees(theta) + 360) % 360;
}

LatLng _destinationPoint(LatLng origin, double bearingDeg, double distanceMeters) {
  const earthRadiusM = 6371000.0;
  final bearing = _toRadians(bearingDeg);
  final lat1 = _toRadians(origin.latitude);
  final lon1 = _toRadians(origin.longitude);
  final angularDistance = distanceMeters / earthRadiusM;

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angularDistance) +
        math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
  );
  final lon2 = lon1 +
      math.atan2(
        math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
        math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
      );

  return LatLng(_toDegrees(lat2), _toDegrees(lon2));
}

double _toRadians(double degrees) => degrees * math.pi / 180;
double _toDegrees(double radians) => radians * 180 / math.pi;

/// Chevron pointing up (north); rotated by segment bearing at placement time.
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = ui.Path()
      ..moveTo(w * 0.5, h * 0.12)
      ..lineTo(w * 0.88, h * 0.62)
      ..lineTo(w * 0.5, h * 0.88)
      ..lineTo(w * 0.12, h * 0.62)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}
