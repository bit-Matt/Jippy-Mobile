import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/widgets/user_location_marker.dart';

/// Lean routes-map style canvas for Go: vector or raster tiles and markers.
class GoMapCanvas extends StatelessWidget {
  const GoMapCanvas({
    super.key,
    required this.mapController,
    required this.vectorStyle,
    required this.initialCenter,
    required this.initialZoom,
    required this.onMapTap,
    required this.routePolylines,
    required this.dropOffPoints,
    required this.userPosition,
    required this.origin,
    required this.destination,
    required this.osmTileUrl,
    required this.userAgentPackageName,
    this.userHeading,
    this.userSpeedMps,
    this.userAccuracyMeters,
    this.onPositionChanged,
    this.onMapReady,
  });

  final MapController mapController;
  final Style? vectorStyle;
  final LatLng initialCenter;
  final double initialZoom;
  final TapCallback onMapTap;
  final List<Polyline<Object>> routePolylines;
  final List<LatLng> dropOffPoints;
  final LatLng? userPosition;
  final LatLng? origin;
  final LatLng? destination;
  final String osmTileUrl;
  final String userAgentPackageName;
  final double? userHeading;
  final double? userSpeedMps;
  final double? userAccuracyMeters;
  final void Function(MapCamera camera, bool hasGesture)? onPositionChanged;
  final VoidCallback? onMapReady;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    if (origin != null) {
      markers.add(
        Marker(
          point: origin!,
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            Icons.place_rounded,
            color: MapColors.primary,
            size: 34,
          ),
        ),
      );
    }
    if (destination != null) {
      markers.add(
        Marker(
          point: destination!,
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(Icons.place, color: MapColors.secondary, size: 34),
        ),
      );
    }
    for (final dropOff in dropOffPoints) {
      markers.add(
        Marker(
          point: dropOff,
          width: 22,
          height: 22,
          alignment: Alignment.center,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF9E9E9E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      );
    }
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        backgroundColor: MapColors.background,
        onTap: onMapTap,
        onPositionChanged: onPositionChanged == null
            ? null
            : (MapCamera camera, bool hasGesture) =>
                onPositionChanged!(camera, hasGesture),
        maxZoom: 18,
        onMapReady: onMapReady,
      ),
      children: [
        if (vectorStyle != null)
          VectorTileLayer(
            tileProviders: vectorStyle!.providers,
            theme: vectorStyle!.theme,
            sprites: vectorStyle!.sprites,
          )
        else
          TileLayer(
            urlTemplate: osmTileUrl,
            userAgentPackageName: userAgentPackageName,
            tileProvider: NetworkTileProvider(
              headers: {
                'User-Agent':
                    'JippyMobile/1.0 (https://github.com/bit-matt/jippy-mobile)',
              },
            ),
          ),
        if (routePolylines.isNotEmpty)
          PolylineLayer<Object>(polylines: routePolylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
        ...buildUserLocationLayers(
          position: userPosition,
          headingDegrees: userHeading,
          speedMps: userSpeedMps,
          accuracyMeters: userAccuracyMeters,
        ),
        RichAttributionWidget(
          animationConfig: const ScaleRAWA(),
          showFlutterMapAttribution: false,
          attributions: const [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}
