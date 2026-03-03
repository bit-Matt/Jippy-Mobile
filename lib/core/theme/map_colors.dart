import 'package:flutter/material.dart';

/// Design system colors and stroke widths for map route rendering.
/// Used for polylines (jeepney routes, walking paths, A* result segments).
class MapColors {
  MapColors._();

  // --- Design system (from design_system.md) ---
  static const Color background = Color(0xFFfefaf5); // Off-white
  static const Color text = Color(0xFF0d0902); // Dark ink
  static const Color primary = Color(0xFFe68c1e); // Jippy Orange - jeepney routes
  static const Color secondary = Color(0xFF87dcf1); // Transit Blue - walking paths
  static const Color accent = Color(0xFF6f57ec); // Jeepney Purple - selected / tricycle

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
}
