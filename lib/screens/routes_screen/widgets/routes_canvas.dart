import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/widgets/user_location_marker.dart';

class RoutesCanvas extends StatelessWidget {
  const RoutesCanvas({
    super.key,
    required this.mapController,
    required this.vectorStyle,
    required this.initialCenter,
    required this.initialZoom,
    required this.onMapTap,
    required this.routePolylines,
    required this.showOverlapRadius,
    required this.overlapTapCenter,
    required this.overlapTapRadiusMeters,
    required this.closurePolygons,
    required this.closureHitNotifier,
    required this.closureLabelMarkers,
    required this.stationMarkers,
    required this.showStations,
    required this.userPosition,
    required this.osmTileUrl,
    required this.userAgentPackageName,
    this.userHeading,
    this.userSpeedMps,
    this.userAccuracyMeters,
  });

  final MapController mapController;
  final Style? vectorStyle;
  final LatLng initialCenter;
  final double initialZoom;
  final TapCallback onMapTap;
  final List<Polyline<Object>> routePolylines;
  final bool showOverlapRadius;
  final LatLng? overlapTapCenter;
  final double? overlapTapRadiusMeters;
  final List<Polygon<Object>> closurePolygons;
  final LayerHitNotifier<String> closureHitNotifier;
  final List<Marker> closureLabelMarkers;
  final List<Marker> stationMarkers;
  final bool showStations;
  final LatLng? userPosition;
  final String osmTileUrl;
  final String userAgentPackageName;
  final double? userHeading;
  final double? userSpeedMps;
  final double? userAccuracyMeters;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        backgroundColor: MapColors.background,
        onTap: onMapTap,
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
        PolylineLayer<Object>(polylines: routePolylines),
        if (showOverlapRadius &&
            overlapTapCenter != null &&
            overlapTapRadiusMeters != null)
          CircleLayer(
            circles: [
              CircleMarker<Object>(
                point: overlapTapCenter!,
                useRadiusInMeter: true,
                radius: overlapTapRadiusMeters!,
                color: MapColors.primary.withValues(alpha: 0.14),
                borderColor: MapColors.primary.withValues(alpha: 0.5),
                borderStrokeWidth: 2,
              ),
            ],
          ),
        if (closurePolygons.isNotEmpty)
          PolygonLayer<Object>(
            polygons: closurePolygons,
            hitNotifier: closureHitNotifier,
          ),
        if (closureLabelMarkers.isNotEmpty)
          MarkerLayer(markers: closureLabelMarkers),
        if (showStations && stationMarkers.isNotEmpty)
          MarkerLayer(markers: stationMarkers),
        ...buildUserLocationLayers(
          position: userPosition,
          headingDegrees: userHeading,
          speedMps: userSpeedMps,
          accuracyMeters: userAccuracyMeters,
        ),
        RichAttributionWidget(
          animationConfig: const ScaleRAWA(),
          showFlutterMapAttribution: false,
          attributions: [const TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}
