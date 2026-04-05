import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../core/theme/map_colors.dart';
import '../data/map_data_loader.dart';
import '../data/valhalla_route_client.dart';
import '../models/jeepney_route.dart';
import '../models/road_closure.dart';
import '../models/routes_and_stations_data.dart';
import '../utils/polyline_1e6.dart';

/// Default center for the map: Iloilo City, Philippines.
final LatLng _iloiloCenter = LatLng(10.7202, 122.5621);

enum _RouteDirection { goingTo, goingBack }

/// Initial zoom level so the city and jeepney routes are visible.
const double _initialZoom = 14.0;

/// OSM tile layer URL. Use [userAgentPackageName] to comply with OSM tile usage policy.
/// For production, consider switching to a dedicated tile provider (MapTiler, Stadia, etc.).
const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Vector tile style (MapLibre/Mapbox style.json) served by our tile server.
const String _vectorStyleUrl =
    'https://jippy.shinosawa-laboratories.dev/tileserver/style.json';

/// App package name for OSM User-Agent (required to avoid tile request blocks).
const String _userAgentPackageName = 'com.example.jippy_mobile';

/// Distance filter (meters) for position updates so the dot does not jump every second.
const int _positionStreamDistanceFilterMeters = 8;

/// Debug-only diagnostics for route polylines (decoded vs fallback).
const bool _debugPolylineDiagnostics = kDebugMode;

/// Temporary UI toggle to hide the search bar overlay.
const bool _showSearchBar = false;
const Color _closureColor = Color(0xFFE81123);
const double _closureFillOpacity = 0.25;
const double _closureStrokeWidth = 2;

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
  DateTime? _lastNavRefreshAt;

  /// Loaded routes and stations from API (or asset fallback).
  RoutesAndStationsData? _mapData;

  /// Loaded vector style. When null, we fall back to raster OSM tiles.
  Style? _vectorStyle;

  /// True while routes are being fetched and during the first render pass.
  bool _loadingRoutes = true;

  /// Selected route IDs currently visible on the map.
  Set<String>? _selectedRouteIds;

  /// Selected route for details panel mode.
  JeepneyRoute? _selectedRouteForDetails;
  bool _showingRouteDetails = false;

  /// When true, tricycle stations are shown.
  bool _showStations = true;

  /// Road-aligned route points fetched from Valhalla (when API polylines missing).
  /// Key format: `${route.id}_goingTo` / `${route.id}_goingBack`.
  Map<String, List<LatLng>> _roadAlignedPointsByKey = <String, List<LatLng>>{};
  final LayerHitNotifier<String> _closureHitNotifier = ValueNotifier(null);
  bool _isShowingClosureSheet = false;

  Set<String> get _selectedRouteIdsSafe => _selectedRouteIds ??= <String>{};

  /// Prevents log spam by only printing when the signature changes.
  String? _lastPolylineDiagnosticsSignature;

  Set<String> get _allRouteIds =>
      (_mapData?.routes ?? const <JeepneyRoute>[]).map((r) => r.id).toSet();

  bool get _areAllRoutesSelected {
    final all = _allRouteIds;
    if (all.isEmpty) return false;
    final selected = _selectedRouteIdsSafe;
    return selected.length == all.length && selected.containsAll(all);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _closureHitNotifier.addListener(_onClosureLayerHit);
    _loadVectorStyle();
    _initLocation();
    _loadMapData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadVectorStyle();
      _loadMapData();
    }
  }

  Future<void> _loadVectorStyle() async {
    // Best-effort: if this fails (no internet, server down), we keep using the
    // default raster OSM layer.
    try {
      final style = await StyleReader(
        uri: _vectorStyleUrl,
        httpHeaders: const {
          'User-Agent':
              'JippyMobile/1.0 (https://jippy.shinosawa-laboratories.dev)',
        },
      ).read().timeout(const Duration(seconds: 6));

      if (!mounted) return;
      setState(() => _vectorStyle = style);
    } catch (_) {
      if (!mounted) return;
      if (_vectorStyle != null) {
        setState(() => _vectorStyle = null);
      }
    }
  }

  /// Loads routes from API; on failure falls back to asset data.
  Future<void> _loadMapData() async {
    if (!mounted) return;
    setState(() {
      _loadingRoutes = true;
    });
    try {
      final previousAllIds = _allRouteIds;
      final bool wasAllSelected =
          previousAllIds.isNotEmpty &&
          _selectedRouteIdsSafe.length == previousAllIds.length &&
          _selectedRouteIdsSafe.containsAll(previousAllIds);

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

          // Selection semantics:
          // - First load: select all routes by default (map shows all, list highlights all).
          // - If user previously hid all routes (empty selection), keep it empty.
          // - If user previously had "all selected", keep it "all selected" after refresh.
          // - Otherwise, keep existing partial selection and drop missing IDs.
          if (_selectedRouteIds == null) {
            _selectedRouteIdsSafe.addAll(incomingRouteIds);
          } else if (_selectedRouteIdsSafe.isEmpty) {
            // Keep empty.
          } else if (wasAllSelected) {
            _selectedRouteIdsSafe
              ..clear()
              ..addAll(incomingRouteIds);
          } else {
            _selectedRouteIdsSafe.removeWhere(
              (id) => !incomingRouteIds.contains(id),
            );
          }
        });
        _completeRouteLoadingAfterRender();
        _fetchValhallaRoutesForMapData(data);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _mapData = const RoutesAndStationsData(
            routes: [],
            stations: [],
            closures: [],
          );
          _selectedRouteIdsSafe.clear();
        });
        _completeRouteLoadingAfterRender();
      }
    }
  }

  void _completeRouteLoadingAfterRender() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _loadingRoutes = false);
    });
  }

  /// Fetches road-aligned geometry from Valhalla for each route direction; updates state on success.
  /// If the Valhalla status check fails, skips requests so routes stay as straight segments.
  Future<void> _fetchValhallaRoutesForMapData(
    RoutesAndStationsData data,
  ) async {
    final available = await checkValhallaStatus().catchError((_) => false);
    if (!available || !mounted) return;
    for (final route in data.routes) {
      if (route.goingTo.length >= 2) {
        final key = '${route.id}_goingTo';
        fetchRoadAlignedRoute(route.goingTo)
            .then((points) {
              if (mounted) {
                setState(() {
                  _roadAlignedPointsByKey = Map.of(_roadAlignedPointsByKey)
                    ..[key] = points;
                });
              }
            })
            .catchError((_) {});
      }
      if (route.goingBack.length >= 2) {
        final key = '${route.id}_goingBack';
        fetchRoadAlignedRoute(route.goingBack)
            .then((points) {
              if (mounted) {
                setState(() {
                  _roadAlignedPointsByKey = Map.of(_roadAlignedPointsByKey)
                    ..[key] = points;
                });
              }
            })
            .catchError((_) {});
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
    _closureHitNotifier.removeListener(_onClosureLayerHit);
    _closureHitNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vectorStyle = _vectorStyle;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _iloiloCenter,
                initialZoom: _initialZoom,
                backgroundColor: MapColors.background,
              ),
              children: [
                if (vectorStyle != null)
                  VectorTileLayer(
                    tileProviders: vectorStyle.providers,
                    theme: vectorStyle.theme,
                    sprites: vectorStyle.sprites,
                  )
                else
                  TileLayer(
                    urlTemplate: _osmTileUrl,
                    userAgentPackageName: _userAgentPackageName,
                    tileProvider: NetworkTileProvider(
                      headers: {
                        'User-Agent':
                            'JippyMobile/1.0 (https://jippy.shinosawa-laboratories.dev)',
                      },
                    ),
                  ),
                // Polylines for static jeepney routes and A* path.
                PolylineLayer<Object>(polylines: _routePolylines),
                if (_closurePolygons.isNotEmpty)
                  PolygonLayer<Object>(
                    polygons: _closurePolygons,
                    hitNotifier: _closureHitNotifier,
                  ),
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
                  attributions: [
                    const TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          if (_showSearchBar) _buildSearchBar(context),
          _buildMapActionButtons(context),
          _buildBottomDrawer(context),
          if (_loadingRoutes) _buildLoadingOverlay(),
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

  /// Polylines to draw (jeepney routes: goingTo and goingBack).
  ///
  /// Prefers encoded polylines from the API (`polylineGoingTo` / `polylineGoingBack`).
  /// Falls back to straight segments between the stored waypoints.
  List<Polyline<Object>> get _routePolylines {
    final routes = _visibleRoutes;
    final polylines = <Polyline<Object>>[];
    final diagParts = <String>[];
    for (final route in routes) {
      final routeColor = _parseRouteColor(route.routeColor);
      for (final direction in _RouteDirection.values) {
        final encoded = direction == _RouteDirection.goingTo
            ? route.polylineGoingTo
            : route.polylineGoingBack;

        List<LatLng> points = const <LatLng>[];
        bool usedDecoded = false;
        bool usedValhalla = false;
        if (encoded != null && encoded.trim().isNotEmpty) {
          final decoded = decodeApiRoutePolyline(encoded);
          if (decoded != null) {
            points = decoded;
            usedDecoded = true;
          }
        }

        if (points.length < 2) {
          final key = direction == _RouteDirection.goingTo
              ? '${route.id}_goingTo'
              : '${route.id}_goingBack';
          final valhallaPoints = _roadAlignedPointsByKey[key];
          if (valhallaPoints != null && valhallaPoints.length >= 2) {
            points = valhallaPoints;
            usedValhalla = true;
          } else {
            final list = direction == _RouteDirection.goingTo
                ? route.goingTo
                : route.goingBack;
            if (list.length < 2) continue;
            final sorted = List.of(list)
              ..sort((a, b) => a.sequence.compareTo(b.sequence));
            points = sorted.map((p) => LatLng(p.lat, p.lon)).toList();
          }
        }

        if (points.length < 2) continue;
        if (_debugPolylineDiagnostics) {
          final dirLabel = direction == _RouteDirection.goingTo ? 'to' : 'back';
          diagParts.add(
            '${route.id}:$dirLabel:${usedDecoded ? 'decoded' : (usedValhalla ? 'valhalla' : 'fallback')}:${points.length}',
          );
        }
        polylines.add(
          Polyline<Object>(
            points: points,
            color: usedDecoded || usedValhalla
                ? routeColor
                : routeColor.withValues(
                    alpha: 0.35,
                  ), // visually obvious fallback
            strokeWidth: usedDecoded || usedValhalla
                ? MapColors.jeepneyRouteStrokeWidth
                : (MapColors.jeepneyRouteStrokeWidth - 1)
                      .clamp(1, 999)
                      .toDouble(),
          ),
        );
      }
    }

    if (_debugPolylineDiagnostics && diagParts.isNotEmpty) {
      final signature = diagParts.join('|');
      if (signature != _lastPolylineDiagnosticsSignature) {
        _lastPolylineDiagnosticsSignature = signature;
        debugPrint('PolylineDiagnostics: $signature');
      }
    }
    return polylines;
  }

  List<JeepneyRoute> get _visibleRoutes {
    final routes = _mapData?.routes ?? const <JeepneyRoute>[];
    if (_selectedRouteIdsSafe.isEmpty) return const <JeepneyRoute>[];
    return routes.where((r) => _selectedRouteIdsSafe.contains(r.id)).toList();
  }

  List<Polygon<Object>> get _closurePolygons {
    final closures = _mapData?.closures ?? const [];
    final polygons = <Polygon<Object>>[];

    for (final closure in closures) {
      if (!closure.canRenderPolygon) continue;
      final ordered = closure.orderedPoints;

      final points = ordered.map((p) => LatLng(p.lat, p.lng)).toList();
      if (points.length < 3) continue;

      polygons.add(
        Polygon<Object>(
          points: points,
          color: _closureColor.withValues(alpha: _closureFillOpacity),
          borderColor: _closureColor,
          borderStrokeWidth: _closureStrokeWidth,
          hitValue: closure.id,
        ),
      );
    }
    return polygons;
  }

  void _onClosureLayerHit() {
    if (!mounted || _isShowingClosureSheet) return;
    final hit = _closureHitNotifier.value;
    final hitId = hit?.hitValues.isNotEmpty == true
        ? hit!.hitValues.first
        : null;
    if (hitId == null) return;

    final closures = _mapData?.closures ?? const <RoadClosure>[];
    RoadClosure? selected;
    for (final closure in closures) {
      if (closure.id == hitId) {
        selected = closure;
        break;
      }
    }
    if (selected == null) return;
    _showClosureDetailsSheet(selected);
  }

  Future<void> _showClosureDetailsSheet(RoadClosure closure) async {
    _isShowingClosureSheet = true;
    final title = closure.closureName.trim().isEmpty
        ? '(untitled)'
        : closure.closureName.trim();
    final description = closure.closureDescription.trim().isEmpty
        ? 'No description available.'
        : closure.closureDescription.trim();

    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: MapColors.background,
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: MapColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: const TextStyle(
                      color: MapColors.text,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      _isShowingClosureSheet = false;
    }
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
    final allIds = allRoutes.map((r) => r.id).toSet();
    setState(() {
      _selectedRouteIdsSafe
        ..clear()
        ..addAll(allIds);
    });
    _fitRoutesBounds(allRoutes);
  }

  void _openRouteDetails(JeepneyRoute route) {
    setState(() {
      _selectedRouteForDetails = route;
      _showingRouteDetails = true;
    });
  }

  void _closeRouteDetails() {
    setState(() {
      _showingRouteDetails = false;
    });
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

  /// Tricycle station markers (white circle, purple border, tricycle icon).
  List<Marker> get _stationMarkers {
    final stations = _mapData?.stations ?? [];
    return stations
        .map(
          (s) => Marker(
            point: LatLng(s.lat, s.lon),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: MapColors.accentColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(4),
              child: Image.asset(
                'assets/icons/tricycle.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
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
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _showingRouteDetails
                      ? _buildRouteDetailsView(scrollController)
                      : _buildRoutesListView(scrollController),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: 8),
        Row(
          children: [
            FilterChip(
              label: const Text('Show all routes'),
              selected: _areAllRoutesSelected,
              onSelected: (selected) {
                if (selected) {
                  _showAllRoutes();
                } else {
                  setState(() => _selectedRouteIdsSafe.clear());
                }
              },
              showCheckmark: false,
              selectedColor: MapColors.primary.withValues(alpha: 0.18),
              checkmarkColor: MapColors.primary,
              labelStyle: TextStyle(
                color: _areAllRoutesSelected
                    ? MapColors.primary
                    : MapColors.text.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: _areAllRoutesSelected
                    ? MapColors.primary.withValues(alpha: 0.7)
                    : MapColors.text.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(width: 10),
            FilterChip(
              label: const Text('Show Tricycle Stations'),
              selected: _showStations,
              onSelected: (selected) {
                setState(() => _showStations = selected);
              },
              showCheckmark: false,
              selectedColor: MapColors.accentColor.withValues(alpha: 0.18),
              checkmarkColor: MapColors.accentColor,
              labelStyle: TextStyle(
                color: _showStations
                    ? MapColors.accentColor
                    : MapColors.text.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: _showStations
                    ? MapColors.accentColor.withValues(alpha: 0.7)
                    : MapColors.text.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRoutesList() {
    if (_loadingRoutes) {
      return _buildRoutesLoadingState();
    }

    final routes = List<JeepneyRoute>.from(
      _mapData?.routes ?? const <JeepneyRoute>[],
    )..sort(_compareRouteNumbersAsc);
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

  int _compareRouteNumbersAsc(JeepneyRoute a, JeepneyRoute b) {
    final aRaw = a.routeNumber.trim();
    final bRaw = b.routeNumber.trim();

    final aKey = _routeNumberSortKey(aRaw);
    final bKey = _routeNumberSortKey(bRaw);

    // Primary: numeric prefix when present.
    if (aKey.number != null && bKey.number != null) {
      final n = aKey.number!.compareTo(bKey.number!);
      if (n != 0) return n;
    } else if (aKey.number != null && bKey.number == null) {
      return -1; // numeric route numbers come first
    } else if (aKey.number == null && bKey.number != null) {
      return 1;
    }

    // Secondary: suffix (e.g. 2A after 2).
    final s = aKey.suffix.compareTo(bKey.suffix);
    if (s != 0) return s;

    // Tertiary: full string compare (stable/consistent).
    return aKey.full.compareTo(bKey.full);
  }

  ({int? number, String suffix, String full}) _routeNumberSortKey(String raw) {
    final lower = raw.toLowerCase();
    final match = RegExp(r'^\s*(\d+)').firstMatch(lower);
    final int? number = match != null ? int.tryParse(match.group(1)!) : null;
    final suffix = match != null ? lower.substring(match.end).trim() : lower;
    return (number: number, suffix: suffix, full: lower);
  }

  Widget _buildRoutesLoadingState() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MapColors.primary.withValues(alpha: 0.18)),
        color: MapColors.background,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Row(
        children: const [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading routes...',
              style: TextStyle(
                color: MapColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutesListView(ScrollController scrollController) {
    return ListView(
      key: const ValueKey<String>('routes-list-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _buildRoutesHeader(),
        const SizedBox(height: 16),
        _buildRoutesList(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRouteDetailsView(ScrollController scrollController) {
    final route = _selectedRouteForDetails;
    final detailText = (route != null && route.routeDetails.trim().isNotEmpty)
        ? route.routeDetails.trim()
        : 'No route details available for this route yet.';

    return ListView(
      key: const ValueKey<String>('route-details-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  route?.routeName ?? 'Route details',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MapColors.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _closeRouteDetails,
              style: TextButton.styleFrom(
                foregroundColor: MapColors.primary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(72, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerRight,
              ),
              label: const Text(
                'Back',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              icon: const Icon(Icons.arrow_forward, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: MapColors.primary.withValues(alpha: 0.18),
            ),
            color: MapColors.background,
          ),
          padding: const EdgeInsets.all(14),
          child: Text(
            detailText,
            style: const TextStyle(
              color: MapColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRouteListItem(JeepneyRoute route, {required bool isSelected}) {
    final color = _parseRouteColor(route.routeColor);
    final routeNumber = route.routeNumber.trim().isEmpty
        ? '--'
        : route.routeNumber.trim();

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
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _openRouteDetails(route),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Details',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: color, size: 18),
                  ],
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
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        bottomPadding > 0 ? bottomPadding : 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildBottomNavItem(index: 0, icon: Icons.map_outlined, label: 'Map'),
          _buildBottomNavItem(index: 1, icon: Icons.alt_route, label: 'Routes'),
          _buildBottomNavItem(
            index: 3,
            icon: Icons.person_outline,
            label: 'Settings',
          ),
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
    final color = selected
        ? MapColors.primary
        : MapColors.text.withValues(alpha: 0.35);
    return InkWell(
      onTap: () => _onBottomNavSelected(index),
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

  void _onBottomNavSelected(int index) {
    if (!mounted) return;

    final now = DateTime.now();
    final last = _lastNavRefreshAt;
    // Prevent rapid taps from spamming API/style requests.
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 800)) {
      setState(() => _selectedNavIndex = index);
      return;
    }
    _lastNavRefreshAt = now;

    setState(() => _selectedNavIndex = index);

    // Best-effort refresh when user switches sections.
    _loadVectorStyle();
    _loadMapData();
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
