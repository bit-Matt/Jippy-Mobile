import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

/// Duration of the position tween between GPS fixes.
const Duration _positionTweenDuration = Duration(milliseconds: 750);

/// Inserts the user location rendering layers into a [FlutterMap]:
/// - translucent accuracy halo (meters-accurate circle) when available
/// - smoothly tweened marker (heading arrow while moving, dot when still)
///
/// Returns an empty list when [position] is null.
List<Widget> buildUserLocationLayers({
  required LatLng? position,
  double? headingDegrees,
  double? speedMps,
  double? accuracyMeters,
}) {
  if (position == null) return const <Widget>[];

  final showHeading = headingDegrees != null &&
      !headingDegrees.isNaN &&
      headingDegrees >= 0;

  final layers = <Widget>[];

  if (accuracyMeters != null &&
      accuracyMeters.isFinite &&
      accuracyMeters > 0 &&
      accuracyMeters < 250) {
    layers.add(
      _TweenedCircleLayer(
        target: position,
        accuracyMeters: accuracyMeters,
      ),
    );
  }

  layers.add(
    _TweenedUserMarkerLayer(
      target: position,
      headingDegrees: showHeading ? headingDegrees : null,
    ),
  );

  return layers;
}

/// Interpolates the circle center between GPS fixes so the halo glides
/// alongside the marker instead of snapping.
class _TweenedCircleLayer extends StatefulWidget {
  const _TweenedCircleLayer({
    required this.target,
    required this.accuracyMeters,
  });

  final LatLng target;
  final double accuracyMeters;

  @override
  State<_TweenedCircleLayer> createState() => _TweenedCircleLayerState();
}

class _TweenedCircleLayerState extends State<_TweenedCircleLayer> {
  late LatLng _from = widget.target;
  late LatLng _to = widget.target;

  @override
  void didUpdateWidget(covariant _TweenedCircleLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _from = _to;
      _to = widget.target;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: _positionTweenDuration,
      curve: Curves.linear,
      builder: (context, t, _) {
        final lat = _lerp(_from.latitude, _to.latitude, t);
        final lng = _lerp(_from.longitude, _to.longitude, t);
        return CircleLayer(
          circles: [
            CircleMarker<Object>(
              point: LatLng(lat, lng),
              useRadiusInMeter: true,
              radius: widget.accuracyMeters,
              color: MapColors.userLocationColor.withValues(alpha: 0.06),
              borderColor: MapColors.userLocationColor.withValues(alpha: 0.14),
              borderStrokeWidth: 1,
            ),
          ],
        );
      },
    );
  }
}

/// The actual marker (arrow when moving, dot otherwise). Tweens position and
/// heading smoothly between updates.
class _TweenedUserMarkerLayer extends StatefulWidget {
  const _TweenedUserMarkerLayer({
    required this.target,
    required this.headingDegrees,
  });

  final LatLng target;
  final double? headingDegrees;

  @override
  State<_TweenedUserMarkerLayer> createState() =>
      _TweenedUserMarkerLayerState();
}

class _TweenedUserMarkerLayerState extends State<_TweenedUserMarkerLayer> {
  late LatLng _fromPos = widget.target;
  late LatLng _toPos = widget.target;
  double? _fromHeading;
  double? _toHeading;

  @override
  void initState() {
    super.initState();
    _fromHeading = widget.headingDegrees;
    _toHeading = widget.headingDegrees;
  }

  @override
  void didUpdateWidget(covariant _TweenedUserMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _fromPos = _toPos;
      _toPos = widget.target;
    }
    if (oldWidget.headingDegrees != widget.headingDegrees) {
      _fromHeading = _toHeading;
      _toHeading = widget.headingDegrees;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: _positionTweenDuration,
      curve: Curves.linear,
      builder: (context, t, _) {
        final lat = _lerp(_fromPos.latitude, _toPos.latitude, t);
        final lng = _lerp(_fromPos.longitude, _toPos.longitude, t);

        final from = _fromHeading;
        final to = _toHeading;
        double? heading;
        if (from != null && to != null) {
          heading = _lerpHeading(from, to, t);
        } else {
          heading = to;
        }

        return MarkerLayer(
          markers: [
            Marker(
              point: LatLng(lat, lng),
              width: 60,
              height: 60,
              alignment: Alignment.center,
              child: _UserMarkerVisual(headingDegrees: heading),
            ),
          ],
        );
      },
    );
  }
}

class _UserMarkerVisual extends StatelessWidget {
  const _UserMarkerVisual({required this.headingDegrees});

  final double? headingDegrees;

  @override
  Widget build(BuildContext context) {
    if (headingDegrees == null) {
      return _buildDot();
    }
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: headingDegrees! * math.pi / 180,
            child: CustomPaint(
              size: const Size(52, 52),
              painter: _HeadingConePainter(),
            ),
          ),
          _buildDot(),
        ],
      ),
    );
  }

  Widget _buildDot() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: MapColors.userLocationColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// Draws the translucent "cone of motion" fan behind the user dot.
class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const sweep = math.pi / 2.2; // ~82 deg cone
    final start = -math.pi / 2 - sweep / 2;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = RadialGradient(
      colors: [
        MapColors.accentColor.withValues(alpha: 0.55),
        MapColors.accentColor.withValues(alpha: 0.08),
      ],
      stops: const [0.0, 1.0],
    );

    final paint = Paint()..shader = gradient.createShader(rect);

    final path = ui.Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(rect, start, sweep, false)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) => false;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Interpolates heading in degrees along the shorter arc (handles wrap-around
/// at 360/0).
double _lerpHeading(double from, double to, double t) {
  var diff = (to - from) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  final result = from + diff * t;
  return (result + 360) % 360;
}
