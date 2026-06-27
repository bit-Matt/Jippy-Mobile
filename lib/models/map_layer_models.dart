import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// One route or leg polyline strand for MapLibre rendering.
class MapPolylineSpec {
  const MapPolylineSpec({
    required this.points,
    required this.color,
    required this.width,
    this.dashArray,
    this.showOutline = false,
  });

  final List<LatLng> points;
  final Color color;
  final int width;
  final List<int>? dashArray;

  /// When true, draws a wider gray polyline underneath this strand.
  final bool showOutline;
}

/// One filled polygon overlay (regions, road closures, etc.).
class MapPolygonSpec {
  const MapPolygonSpec({
    required this.points,
    required this.fillColor,
    required this.outlineColor,
    this.id,
    this.outlineWidth = 0,
    this.outlineDashArray,
  });

  final List<LatLng> points;
  final Color fillColor;
  final Color outlineColor;

  /// Optional identifier used for tap hit-testing (e.g. closure id).
  final String? id;

  /// When greater than zero, draws a [PolylineLayer] border at this width
  /// (pixels) instead of the default 1px fill outline.
  final int outlineWidth;

  /// Dash pattern for [outlineWidth] borders (e.g. `[5, 4]`).
  final List<int>? outlineDashArray;
}

/// A map-aligned Flutter widget marker (arrows, pins, station icons).
class MapWidgetMarkerSpec {
  const MapWidgetMarkerSpec({
    required this.point,
    required this.size,
    required this.child,
    this.alignment = Alignment.center,
    this.onTap,
  });

  final LatLng point;
  final Size size;
  final Widget child;
  final Alignment alignment;

  /// When set, the marker receives taps (see [JippyMapCanvas] widget marker layer).
  final VoidCallback? onTap;
}

/// A pixel-radius circle overlay spec (overlap radius, etc.).
class MapCircleSpec {
  const MapCircleSpec({
    required this.point,
    required this.radiusPixels,
    required this.color,
    required this.strokeColor,
    this.strokeWidth = 0,
  });

  final LatLng point;
  final int radiusPixels;
  final Color color;
  final Color strokeColor;
  final int strokeWidth;
}
