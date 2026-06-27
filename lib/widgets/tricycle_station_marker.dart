import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/models/map_layer_models.dart';

/// Shared sizing for tricycle station markers on map screens.
class TricycleMarkerStyle {
  TricycleMarkerStyle._();

  static const double markerSize = 28;
  static const double iconSize = 18;
  static const double padding = 3;
  static const double borderWidth = 1.5;
}

/// Builds a map marker for a tricycle waiting station.
MapWidgetMarkerSpec buildTricycleStationMarker({
  required LatLng point,
  VoidCallback? onTap,
}) {
  return MapWidgetMarkerSpec(
    point: point,
    size: const Size(
      TricycleMarkerStyle.markerSize,
      TricycleMarkerStyle.markerSize,
    ),
    onTap: onTap,
    child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: MapColors.accentColor,
            width: TricycleMarkerStyle.borderWidth,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              spreadRadius: 0,
            ),
          ],
        ),
        padding: const EdgeInsets.all(TricycleMarkerStyle.padding),
        child: Image.asset(
          'assets/icons/tricycle.png',
          width: TricycleMarkerStyle.iconSize,
          height: TricycleMarkerStyle.iconSize,
          fit: BoxFit.contain,
        ),
      ),
  );
}
