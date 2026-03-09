import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme/map_colors.dart';
import '../data/map_data_loader.dart';
import '../models/routes_and_stations_data.dart';

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
  int _selectedNavIndex = 1;

  /// Loaded routes and stations from dashboard API (sample asset for now).
  RoutesAndStationsData? _mapData;
  /// When true, tricycle stations are shown. Ready for future checkbox UI.
  bool _showStations = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    final data = await loadSampleMapData();
    if (mounted) setState(() => _mapData = data);
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
              // Polylines for static jeepney routes and A* path.
              PolylineLayer<Object>(polylines: _routePolylines),
              if (_showStations && _mapData != null && _mapData!.stations.isNotEmpty)
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

  /// Polylines to draw (static jeepney routes from API; A* path can be appended later).
  List<Polyline<Object>> get _routePolylines {
    final routes = _mapData?.routes ?? [];
    final polylines = <Polyline<Object>>[];
    for (final route in routes) {
      final sorted = List.of(route.points)..sort((a, b) => a.sequence.compareTo(b.sequence));
      final points = sorted.map((p) => LatLng(p.lat, p.lon)).toList();
      if (points.length < 2) continue;
      final color = _parseRouteColor(route.routeColor);
      polylines.add(Polyline<Object>(
        points: points,
        color: color,
        strokeWidth: MapColors.jeepneyRouteStrokeWidth,
      ));
    }
    return polylines;
  }

  /// Tricycle station markers (accent color, distinct from user dot).
  List<Marker> get _stationMarkers {
    final stations = _mapData?.stations ?? [];
    return stations
        .map((s) => Marker(
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
            ))
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

  /// Draggable bottom panel with route chips and mobile bottom nav.
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
                    const SizedBox(height: 12),
                    _buildRouteChipsRow(),
                    const SizedBox(height: 16),
                    _buildCurrentlyViewingCard(),
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
          onPressed: () {
            // TODO: Push routes list screen.
          },
          style: TextButton.styleFrom(
            foregroundColor: MapColors.primary,
            padding: EdgeInsets.zero,
            minimumSize: const Size(56, 24),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'See all',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteChipsRow() {
    final chips = _routeChips;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            _buildRouteChip(chips[i]),
            if (i != chips.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteChip(_RouteChipViewData chip) {
    final bool isActive = chip.isActive;
    return SizedBox(
      width: 58,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: chip.background,
              borderRadius: BorderRadius.circular(14),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              chip.code,
              style: TextStyle(
                color: isActive ? Colors.white : MapColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isActive ? 'ACTIVE' : 'OFF',
            style: TextStyle(
              color: isActive ? chip.background : MapColors.text.withValues(alpha: 0.35),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentlyViewingCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MapColors.primary.withValues(alpha: 0.18)),
        color: MapColors.background,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENTLY VIEWING',
                  style: TextStyle(
                    color: MapColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _currentRouteLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MapColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _buildOverlappingRouteBadges(),
        ],
      ),
    );
  }

  Widget _buildOverlappingRouteBadges() {
    final active = _activeRouteCodes;
    if (active.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: active.length > 1 ? 56 : 26,
      height: 26,
      child: Stack(
        children: [
          for (int i = 0; i < active.length && i < 2; i++)
            Positioned(
              left: i * 22,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: i == 0 ? MapColors.primary : MapColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: MapColors.background, width: 1.4),
                ),
                alignment: Alignment.center,
                child: Text(
                  active[i],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
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
          _buildBottomNavItem(index: 2, icon: Icons.bookmark_border, label: 'Saved'),
          _buildBottomNavItem(index: 3, icon: Icons.person_outline, label: 'Profile'),
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

  List<_RouteChipViewData> get _routeChips {
    final routes = _mapData?.routes ?? const [];
    if (routes.isEmpty) {
      return const [
        _RouteChipViewData(code: '01A', isActive: true, background: MapColors.primary),
        _RouteChipViewData(code: '03B', isActive: true, background: MapColors.accent),
        _RouteChipViewData(code: '08A', isActive: false, background: Color(0xFFE8E5E1)),
        _RouteChipViewData(code: '12C', isActive: false, background: Color(0xFFE8E5E1)),
        _RouteChipViewData(code: '07D', isActive: false, background: Color(0xFFE8E5E1)),
      ];
    }

    final list = <_RouteChipViewData>[];
    final count = routes.length < 5 ? routes.length : 5;
    for (int i = 0; i < count; i++) {
      final isActive = i < 2;
      list.add(
        _RouteChipViewData(
          code: routes[i].routeNumber,
          isActive: isActive,
          background: isActive
              ? (i == 0 ? MapColors.primary : MapColors.accent)
              : const Color(0xFFE8E5E1),
        ),
      );
    }
    return list;
  }

  List<String> get _activeRouteCodes {
    return _routeChips.where((chip) => chip.isActive).take(2).map((chip) => chip.code).toList();
  }

  String get _currentRouteLabel {
    final routes = _mapData?.routes;
    if (routes == null || routes.isEmpty) {
      return 'Jaro CPU-City Proper Loop';
    }
    return routes.first.routeName;
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

class _RouteChipViewData {
  const _RouteChipViewData({
    required this.code,
    required this.isActive,
    required this.background,
  });

  final String code;
  final bool isActive;
  final Color background;
}
