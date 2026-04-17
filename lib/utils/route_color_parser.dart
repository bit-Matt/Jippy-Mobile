import 'package:flutter/material.dart';

import '../core/theme/map_colors.dart';

/// Parses hex route color (e.g. "#009e49"), with fallback to map theme color.
Color parseRouteColor(String hex) {
  try {
    String s = hex.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  } catch (_) {
    return MapColors.jeepneyRouteColor;
  }
}
