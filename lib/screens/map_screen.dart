import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme/map_colors.dart';

/// Default center for the map: Iloilo City, Philippines.
final LatLng _iloiloCenter = LatLng(10.7202, 122.5621);

/// Initial zoom level so the city and jeepney routes are visible.
const double _initialZoom = 14.0;

/// OSM tile layer URL. Use [userAgentPackageName] to comply with OSM tile usage policy.
/// For production, consider switching to a dedicated tile provider (MapTiler, Stadia, etc.).
const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// App package name for OSM User-Agent (required to avoid tile request blocks).
const String _userAgentPackageName = 'com.example.jippy_mobile';

/// Distance filter (meters) for position updates so the dot does not jump every second.
const int _positionStreamDistanceFilterMeters = 8;

/// Full-screen map with OpenStreetMap tiles, user location dot, and structure for
/// static route polylines and A* path segments.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  Position? _userPosition;
  StreamSubscription<Position>? _positionSubscription;
  LocationPermission? _locationPermission;
  bool _permissionChecked = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _permissionChecked = true;
        _locationPermission = null; // service disabled
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    setState(() {
      _permissionChecked = true;
      _locationPermission = permission;
    });

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final stream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: _positionStreamDistanceFilterMeters,
      ),
    );
    _positionSubscription = stream.listen(
      (Position position) {
        if (mounted) {
          setState(() => _userPosition = position);
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _userPosition = null);
        }
      },
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _iloiloCenter,
              initialZoom: _initialZoom,
              backgroundColor: MapColors.background,
            ),
            children: [
              TileLayer(
                urlTemplate: _osmTileUrl,
                userAgentPackageName: _userAgentPackageName,
              ),
              // Polylines for static jeepney routes and A* path (empty until route data exists).
              PolylineLayer<Object>(
                polylines: _routePolylines,
              ),
              if (_userPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _userPosition!.latitude,
                        _userPosition!.longitude,
                      ),
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: MapColors.userLocationColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              RichAttributionWidget(
                animationConfig: const ScaleRAWA(),
                showFlutterMapAttribution: false,
                attributions: [
                  const TextSourceAttribution(
                    'OpenStreetMap contributors',
                  ),
                ],
              ),
            ],
          ),
          if (_permissionChecked &&
              (_locationPermission == LocationPermission.denied ||
                  _locationPermission == LocationPermission.deniedForever ||
                  _locationPermission == null))
            _buildLocationMessage(
              _locationPermission == null
                  ? 'Location service is disabled.'
                  : 'Location permission denied. Enable it to see your position on the map.',
            ),
        ],
      ),
    );
  }

  /// Polylines to draw (static routes + selected A* path). Empty until route data is wired.
  List<Polyline<Object>> get _routePolylines => [];

  Widget _buildLocationMessage(String message) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        color: MapColors.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.location_off, color: MapColors.text.withValues(alpha: 0.7)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: MapColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
