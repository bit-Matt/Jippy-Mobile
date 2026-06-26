import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/widgets/user_location_marker.dart';

class TricyclesCanvas extends StatelessWidget {
  const TricyclesCanvas({
    super.key,
    required this.mapController,
    required this.vectorStyle,
    required this.initialCenter,
    required this.initialZoom,
    required this.regionPolygons,
    required this.stationMarkers,
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
  final List<Polygon<Object>> regionPolygons;
  final List<Marker> stationMarkers;
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
        if (regionPolygons.isNotEmpty)
          PolygonLayer<Object>(polygons: regionPolygons),
        if (stationMarkers.isNotEmpty)
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
          attributions: [
            const TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}
