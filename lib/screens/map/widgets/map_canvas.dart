import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

class MapCanvas extends StatelessWidget {
  const MapCanvas({
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
        if (userPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: userPosition!,
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: MapColors.userLocationColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
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
