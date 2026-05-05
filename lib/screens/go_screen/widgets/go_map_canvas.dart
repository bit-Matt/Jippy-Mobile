import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/widgets/user_location_marker.dart';

/// Lean routes-map style canvas for Go: vector or raster tiles, markers, recenter only.
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
          child: Icon(Icons.trip_origin, color: MapColors.primary, size: 32),
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
                    'JippyMobile/1.0 (https://jippy.shinosawa-laboratories.dev)',
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

/// Single recenter control (Go screen does not use layer toggles).
///
/// When [isFollowing] is true, the button renders in its "locked" follow state
/// (filled icon); otherwise it invites the user to re-enable follow mode.
class GoRecenterButton extends StatelessWidget {
  const GoRecenterButton({
    super.key,
    required this.userPosition,
    required this.mapController,
    this.isFollowing = false,
    this.onRecenter,
  });

  final Position? userPosition;
  final MapController mapController;
  final bool isFollowing;
  final VoidCallback? onRecenter;

  @override
  Widget build(BuildContext context) {
    final hasUserPosition = userPosition != null;
    return Positioned(
      right: 16,
      top: MediaQuery.sizeOf(context).height * 0.34,
      child: Material(
        color: hasUserPosition
            ? MapColors.background
            : MapColors.background.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14),
        elevation: hasUserPosition ? 2 : 0,
        child: InkWell(
          onTap: hasUserPosition
              ? () {
                  if (onRecenter != null) {
                    onRecenter!();
                    return;
                  }
                  final position = userPosition;
                  if (position == null) return;
                  mapController.move(
                    LatLng(position.latitude, position.longitude),
                    mapController.camera.zoom,
                  );
                }
              : null,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              isFollowing ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: hasUserPosition
                  ? MapColors.primary
                  : MapColors.text.withValues(alpha: 0.35),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
