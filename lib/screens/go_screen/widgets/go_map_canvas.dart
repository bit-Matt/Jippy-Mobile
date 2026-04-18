import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

/// Lean routes-map style canvas for Go: vector or raster tiles, markers, recenter only.
class GoMapCanvas extends StatelessWidget {
  const GoMapCanvas({
    super.key,
    required this.mapController,
    required this.vectorStyle,
    required this.initialCenter,
    required this.initialZoom,
    required this.onMapTap,
    required this.userPosition,
    required this.origin,
    required this.destination,
    required this.routePolylines,
    required this.routeEndpointMarkers,
    required this.osmTileUrl,
    required this.userAgentPackageName,
  });

  final MapController mapController;
  final Style? vectorStyle;
  final LatLng initialCenter;
  final double initialZoom;
  final TapCallback onMapTap;
  final LatLng? userPosition;
  final LatLng? origin;
  final LatLng? destination;
  final List<Polyline<Object>> routePolylines;
  final List<Marker> routeEndpointMarkers;
  final String osmTileUrl;
  final String userAgentPackageName;

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
    if (routeEndpointMarkers.isNotEmpty) {
      markers.addAll(routeEndpointMarkers);
    }

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
        if (routePolylines.isNotEmpty) PolylineLayer<Object>(polylines: routePolylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
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
                    boxShadow: const [
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
          attributions: const [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

/// Single recenter control (Go screen does not use layer toggles).
class GoRecenterButton extends StatelessWidget {
  const GoRecenterButton({
    super.key,
    required this.userPosition,
    required this.mapController,
  });

  final Position? userPosition;
  final MapController mapController;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: MediaQuery.sizeOf(context).height * 0.34,
      child: Material(
        color: MapColors.background,
        borderRadius: BorderRadius.circular(14),
        elevation: 2,
        child: InkWell(
          onTap: () {
            final position = userPosition;
            if (position == null) return;
            mapController.move(
              LatLng(position.latitude, position.longitude),
              mapController.camera.zoom,
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              Icons.gps_fixed,
              color: MapColors.primary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
