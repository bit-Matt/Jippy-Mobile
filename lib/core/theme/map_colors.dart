import 'package:flutter/material.dart';

/// Domain colors and stroke widths for map route rendering.
///
/// UI chrome should use [ThemeData.colorScheme] instead. These tokens remain
/// for polylines, markers, and other map-domain styling.
class MapColors {
  MapColors._();

  /// Brand seed / jeepney route orange.
  static const Color primary = Color(0xFFe68c1e);

  /// Transit blue — walking paths.
  static const Color secondary = Color(0xFF87dcf1);

  /// Jeepney purple — selected / tricycle.
  static const Color accent = Color(0xFF6f57ec);

  /// Dark ink used for route outlines on the map.
  static const Color text = Color(0xFF0d0902);

  /// Placeholder behind the map canvas while tiles load.
  static const Color mapCanvasPlaceholder = Color(0xFFfefaf5);

  // --- Polyline styling ---

  /// Stroke width (logical pixels) for jeepney route lines.
  static const double jeepneyRouteStrokeWidth = 4.5;

  /// Stroke width for walking segments.
  static const double walkingStrokeWidth = 3.5;

  /// Stroke width for tricycle or accent segments.
  static const double accentStrokeWidth = 4.0;

  /// Color for jeepney route polylines (primary).
  static const Color jeepneyRouteColor = primary;

  /// Color for walking segment polylines (secondary).
  static const Color walkingColor = secondary;

  /// Color for tricycle or selected/accent polylines.
  static const Color accentColor = accent;

  /// Color for the user position dot (primary so it stands out).
  static const Color userLocationColor = primary;

  /// Black halo drawn under route polylines on the map.
  static const Color routeOutlineColor = text;

  /// Extra stroke width (pixels) added to the fill width for route outlines.
  static const int routeOutlineExtraWidth = 2;

  /// Uniform border for unselected route list cards on the map sheet.
  static const Color routeListBorderColor = Color(0xFFBDBDBD);
}
