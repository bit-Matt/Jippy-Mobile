import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme/map_colors.dart';
import '../data/map_data_loader.dart';
import '../data/valhalla_route_client.dart';
import '../models/jeepney_route.dart';
import '../models/routes_and_stations_data.dart';

/// Default center for the map: Iloilo City, Philippines.
final LatLng _iloiloCenter = LatLng(10.7202, 122.5621);

enum _RouteDirection { goingTo, goingBack }

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

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  Position? _userPosition;
  StreamSubscription<Position>? _positionSubscription;
  LocationPermission? _locationPermission;
  bool _permissionChecked = false;
  int _selectedNavIndex = 1;

  /// Loaded routes and stations from API (or asset fallback).
  RoutesAndStationsData? _mapData;
  /// True while fetching routes from API or loading fallback.
  bool _isLoadingMapData = false;
  /// Road-aligned polyline points from Valhalla. Keys: 'routeId_goingTo' / 'routeId_goingBack'. Missing = use straight segments.
  Map<String, List<LatLng>> _roadAlignedPointsByKey = {};
  /// Selected route IDs currently visible on the map.
  Set<String>? _selectedRouteIds;
  /// When true, tricycle stations are shown. Ready for future checkbox UI.
  final bool _showStations = true;

  Set<String> get _selectedRouteIdsSafe => _selectedRouteIds ??= <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
    _loadMapData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMapData();
    }
  }

  /// Loads routes from API; on failure falls back to asset data.
  Future<void> _loadMapData() async {
    if (!mounted) return;
    setState(() => _isLoadingMapData = true);
    try {
      RoutesAndStationsData data;
      try {
        data = await loadRoutesFromApi();
      } catch (_) {
        data = await loadSampleMapData();
      }
      if (mounted) {
        final incomingRouteIds = data.routes.map((r) => r.id).toSet();
        setState(() {
          _mapData = data;
          _isLoadingMapData = false;
          _roadAlignedPointsByKey = {};
          _selectedRouteIdsSafe.removeWhere((id) => !incomingRouteIds.contains(id));
        });
        _fetchValhallaRoutesForMapData(data);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _mapData = const RoutesAndStationsData(routes: [], stations: []);
          _isLoadingMapData = false;
          _roadAlignedPointsByKey = {};
          _selectedRouteIdsSafe.clear();
        });
      }
    }
  }

  /// Fetches road-aligned geometry from Valhalla for each route direction; updates state on success.
  /// If the Valhalla status check fails, skips requests so routes stay as straight segments.
  Future<void> _fetchValhallaRoutesForMapData(RoutesAndStationsData data) async {
    final available = await checkValhallaStatus().catchError((_) => false);
    if (!available || !mounted) return;
    for (final route in data.routes) {
      if (route.goingTo.length >= 2) {
        final key = '${route.id}_goingTo';
        fetchRoadAlignedRoute(route.goingTo).then((points) {
          if (mounted) {
            setState(() {
              _roadAlignedPointsByKey = Map.of(_roadAlignedPointsByKey)..[key] = points;
            });
          }
        }).catchError((_) {});
      }
      if (route.goingBack.length >= 2) {
        final key = '${route.id}_goingBack';
        fetchRoadAlignedRoute(route.goingBack).then((points) {
          if (mounted) {
            setState(() {
              _roadAlignedPointsByKey = Map.of(_roadAlignedPointsByKey)..[key] = points;
            });
          }
        }).catchError((_) {});
      }
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
              // Polylines for static jeepney routes and A* path.
              PolylineLayer<Object>(polylines: _routePolylines),
              if (_showStations &&
                  _mapData != null &&
                  _mapData!.stations.isNotEmpty)
                MarkerLayer(markers: _stationMarkers),
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
                          border: Border.all(color: Colors.white, width: 2),
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
                  const TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          _buildSearchBar(context),
          _buildMapActionButtons(context),
          _buildBottomDrawer(context),
          if (_isLoadingMapData) _buildLoadingOverlay(),
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

  /// Polylines to draw (jeepney routes: goingTo and goingBack, road-aligned from Valhalla when available, else straight segments).
  List<Polyline<Object>> get _routePolylines {
    final routes = _visibleRoutes;
    final polylines = <Polyline<Object>>[];
    for (final route in routes) {
      final routeColor = _parseRouteColor(route.routeColor);
      for (final direction in _RouteDirection.values) {
        final list = direction == _RouteDirection.goingTo ? route.goingTo : route.goingBack;
        if (list.length < 2) continue;
        final key = '${route.id}_${direction.name}';
        List<LatLng> points;
        final roadAligned = _roadAlignedPointsByKey[key];
        if (roadAligned != null && roadAligned.length >= 2) {
          points = roadAligned;
        } else {
          final sorted = List.of(list)..sort((a, b) => a.sequence.compareTo(b.sequence));
          points = sorted.map((p) => LatLng(p.lat, p.lon)).toList();
        }
        if (points.length < 2) continue;
        polylines.add(
          Polyline<Object>(
            points: points,
            color: routeColor,
            strokeWidth: MapColors.jeepneyRouteStrokeWidth,
          ),
        );
      }
    }
    return polylines;
  }

  List<JeepneyRoute> get _visibleRoutes {
    final routes = _mapData?.routes ?? const <JeepneyRoute>[];
    if (_selectedRouteIdsSafe.isEmpty) return routes;
    return routes.where((r) => _selectedRouteIdsSafe.contains(r.id)).toList();
  }

  void _onRouteTap(JeepneyRoute route) {
    late List<JeepneyRoute> routesToFit;
    setState(() {
      // Focus mode: first selection isolates the tapped route.
      if (_selectedRouteIdsSafe.isEmpty) {
        _selectedRouteIdsSafe.add(route.id);
      } else if (_selectedRouteIdsSafe.contains(route.id)) {
        _selectedRouteIdsSafe.remove(route.id);
      } else {
        _selectedRouteIdsSafe.add(route.id);
      }
      routesToFit = _selectedRouteIdsSafe.isEmpty
          ? (_mapData?.routes ?? const <JeepneyRoute>[])
          : _visibleRoutes;
    });

    if (routesToFit.isEmpty) {
      _mapController.move(_iloiloCenter, _initialZoom);
      return;
    }
    _fitRoutesBounds(routesToFit);
  }

  void _showAllRoutes() {
    final allRoutes = _mapData?.routes ?? const <JeepneyRoute>[];
    setState(() {
      _selectedRouteIdsSafe.clear();
    });
    _fitRoutesBounds(allRoutes);
  }

  /// Fits map camera to route points; falls back to city center if no points.
  void _fitRoutesBounds(List<JeepneyRoute> routes) {
    final points = <LatLng>[];
    for (final route in routes) {
      for (final p in route.goingTo) {
        points.add(LatLng(p.lat, p.lon));
      }
      for (final p in route.goingBack) {
        points.add(LatLng(p.lat, p.lon));
      }
    }

    if (points.isEmpty) {
      _mapController.move(_iloiloCenter, _initialZoom);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(32, 110, 32, 300),
        ),
      );
    } catch (_) {
      _mapController.move(bounds.center, _mapController.camera.zoom);
    }
  }

  /// Tricycle station markers (accent color, distinct from user dot).
  List<Marker> get _stationMarkers {
    final stations = _mapData?.stations ?? [];
    return stations
        .map(
          (s) => Marker(
            point: LatLng(s.lat, s.lon),
            width: 20,
            height: 20,
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                color: MapColors.accentColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
        )
        .toList();
  }

  /// Parses hex route color (e.g. "#009e49"); returns [MapColors.jeepneyRouteColor] on failure.
  Color _parseRouteColor(String hex) {
    try {
      String s = hex.trim();
      if (s.startsWith('#')) s = s.substring(1);
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return MapColors.jeepneyRouteColor;
    }
  }

  /// Floating pill-shaped search bar at top (design system: "Where do you want to go?").
  /// Tapping will later expand to full-screen search; placeholder for now.
  Widget _buildSearchBar(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding, left: 16, right: 16),
        child: Material(
          elevation: 2,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(24),
          color: MapColors.background,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(Icons.search, color: MapColors.primary, size: 24),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // TODO: Expand to full-screen search view when implemented.
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Where do you want to go?',
                        style: TextStyle(
                          color: MapColors.text.withValues(alpha: 0.6),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.mic_none,
                    color: MapColors.text.withValues(alpha: 0.7),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Semi-transparent overlay with a circular progress indicator while routes are loading.
  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black26,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// Right-side map actions (layers and recenter).
  Widget _buildMapActionButtons(BuildContext context) {
    return Positioned(
      right: 16,
      top: MediaQuery.sizeOf(context).height * 0.34,
      child: Column(
        children: [
          _mapActionButton(
            icon: Icons.layers_outlined,
            onTap: () {
              // TODO: Toggle map overlays or route layers.
            },
          ),
          const SizedBox(height: 12),
          _mapActionButton(
            icon: Icons.gps_fixed,
            iconColor: MapColors.primary,
            onTap: () {
              final position = _userPosition;
              if (position == null) return;
              _mapController.move(
                LatLng(position.latitude, position.longitude),
                _mapController.camera.zoom,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _mapActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Material(
      color: MapColors.background,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: iconColor ?? MapColors.text.withValues(alpha: 0.75),
            size: 24,
          ),
        ),
      ),
    );
  }

  /// Draggable bottom panel with grab handle, route chips, and mobile bottom nav.
  Widget _buildBottomDrawer(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.38,
      minChildSize: 0.34,
      maxChildSize: 0.74,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: MapColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 78,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MapColors.text.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildRoutesHeader(),
                    const SizedBox(height: 16),
                    _buildRoutesList(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: MapColors.text.withValues(alpha: 0.08),
              ),
              _buildBottomNavBar(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoutesHeader() {
    return Row(
      children: [
        const Text(
          'Routes',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: _showAllRoutes,
          style: TextButton.styleFrom(
            foregroundColor: MapColors.primary,
            padding: EdgeInsets.zero,
            minimumSize: const Size(56, 24),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Show all routes',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildRoutesList() {
    final routes = _mapData?.routes ?? const <JeepneyRoute>[];
    if (routes.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MapColors.primary.withValues(alpha: 0.18)),
          color: MapColors.background,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: const Text(
          'No routes available right now.',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int index = 0; index < routes.length; index++) ...[
          _buildRouteListItem(
            routes[index],
            isSelected: _selectedRouteIdsSafe.contains(routes[index].id),
          ),
          if (index < routes.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildRouteListItem(JeepneyRoute route, {required bool isSelected}) {
    final color = _parseRouteColor(route.routeColor);
    final routeNumber = route.routeNumber.trim().isEmpty ? '--' : route.routeNumber.trim();

    return InkWell(
      onTap: () => _onRouteTap(route),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.18),
            width: isSelected ? 2 : 1,
          ),
          color: MapColors.background,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                routeNumber,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                route.routeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MapColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottomPadding > 0 ? bottomPadding : 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildBottomNavItem(index: 0, icon: Icons.map_outlined, label: 'Map'),
          _buildBottomNavItem(index: 1, icon: Icons.alt_route, label: 'Routes'),
          _buildBottomNavItem(index: 3, icon: Icons.person_outline, label: 'Setting'),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _selectedNavIndex == index;
    final color = selected ? MapColors.primary : MapColors.text.withValues(alpha: 0.35);
    return InkWell(
      onTap: () => setState(() => _selectedNavIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              Icon(
                Icons.location_off,
                color: MapColors.text.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: MapColors.text, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
