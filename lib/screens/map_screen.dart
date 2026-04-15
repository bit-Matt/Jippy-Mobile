import 'dart:async';
import 'dart:math' as math;

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
import 'settings_screen.dart';
import '../utils/polyline_1e6.dart';
import '../utils/route_polyline_hit.dart';

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

/// Logical pixels around the tap treated as "near" a route (converted to meters
/// at tap latitude and zoom via [metersPerPixelAtLatitude]).
const double _overlapTapRadiusLogicalPixels = 38;

/// Clamp for overlap distance (meters): avoids tiny thresholds when zoomed in
/// and excessive matches when zoomed out.
const double _overlapThresholdMetersMin = 28;
const double _overlapThresholdMetersMax = 220;

/// After a map tap for overlap, ensure at least this zoom when nudging the camera.
const double _overlapTapMinZoom = 15;

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

  /// True when the map is showing only a selected subset of routes.
  bool _isFocusedMode = false;

  /// True when route taps can build a comparison set instead of replacing selection.
  bool _isCompareMode = false;

  /// Selected route IDs currently visible on the map.
  Set<String>? _selectedRouteIds;

  /// Selected route for details panel mode.
  JeepneyRoute? _selectedRouteForDetails;
  bool _showingRouteDetails = false;

  /// Selected road closure for in-drawer details (same sheet as routes).
  RoadClosure? _selectedClosureForDetails;
  bool _showingClosureDetails = false;

  /// Map-tap overlap mode: routes whose geometry passes near the tap point.
  bool _showingOverlappingRoutes = false;
  List<JeepneyRoute> _overlappingRoutes = const <JeepneyRoute>[];

  /// When true, closing route details returns to the overlap list instead of the main list.
  bool _returnToOverlappingRoutesAfterDetails = false;

  /// Bumps when route geometry used for hit-testing must be rebuilt.
  int _hitGeometryGeneration = 0;
  List<RouteHitPolyline>? _hitTestPolylineCache;
  int? _hitTestPolylineCacheAtGeneration;
  final Map<String, ({List<LatLng> points, bool usedDecoded, bool usedValhalla})>
      _resolvedDirectionGeometryCache = <String, ({List<LatLng> points, bool usedDecoded, bool usedValhalla})>{};
  int? _resolvedDirectionGeometryCacheAtGeneration;

  /// When true, tricycle stations are shown.
  bool _showStations = true;

  /// Road-aligned route points fetched from Valhalla (when API polylines missing).
  /// Key format: `${route.id}_goingTo` / `${route.id}_goingBack`.
  Map<String, List<LatLng>> _roadAlignedPointsByKey = <String, List<LatLng>>{};
  bool _hasAppliedInitialRouteFit = false;
  final LayerHitNotifier<String> _closureHitNotifier = ValueNotifier(null);

  Set<String> _selectedRouteIdsMutable() {
    _selectedRouteIds ??= <String>{};
    return _selectedRouteIds!;
  }

  Set<String> get _selectedRouteIdsReadOnly =>
      _selectedRouteIds ?? const <String>{};

  /// Prevents log spam by only printing when the signature changes.
  String? _lastPolylineDiagnosticsSignature;

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
          _hitGeometryGeneration++;

          // Selection semantics:
          // - Show All mode keeps every route selected.
          // - Focused mode keeps the current selection set and drops missing IDs.
          // - Single-select focused mode collapses any stale multi-selection to one route.
          if (!_isFocusedMode || _selectedRouteIds == null) {
            _selectedRouteIds = Set<String>.from(incomingRouteIds);
          } else {
            _selectedRouteIds!.removeWhere(
              (id) => !incomingRouteIds.contains(id),
            );
            if (!_isCompareMode && _selectedRouteIds!.length > 1) {
              final retainedRouteId = _selectedRouteIds!.last;
              _selectedRouteIds = <String>{retainedRouteId};
            }
          }
        });
        _completeRouteLoadingAfterRender();
        _fitAllRoutesOnInitialLoad(data.routes);
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
          _selectedRouteIdsMutable().clear();
          _hitGeometryGeneration++;
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

  void _fitAllRoutesOnInitialLoad(List<JeepneyRoute> routes) {
    if (_hasAppliedInitialRouteFit || routes.isEmpty) return;
    _hasAppliedInitialRouteFit = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitRoutesBounds(routes);
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
                  _hitGeometryGeneration++;
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
                  _hitGeometryGeneration++;
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
                onTap: _onMapTapForOverlappingRoutes,
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
                if (_closureLabelMarkers.isNotEmpty)
                  MarkerLayer(markers: _closureLabelMarkers),
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

  /// Shared resolution for drawing, camera fit, and map-tap hit testing.
  ({List<LatLng> points, bool usedDecoded, bool usedValhalla})
  _resolveDirectionGeometry(JeepneyRoute route, _RouteDirection direction) {
    if (_resolvedDirectionGeometryCacheAtGeneration != _hitGeometryGeneration) {
      _resolvedDirectionGeometryCache.clear();
      _resolvedDirectionGeometryCacheAtGeneration = _hitGeometryGeneration;
    }
    final cacheKey = '${route.id}:${direction.name}';
    final cached = _resolvedDirectionGeometryCache[cacheKey];
    if (cached != null) return cached;

    final encoded = direction == _RouteDirection.goingTo
        ? route.polylineGoingTo
        : route.polylineGoingBack;

    List<LatLng> points = const <LatLng>[];
    var usedDecoded = false;
    var usedValhalla = false;

    if (encoded != null && encoded.trim().isNotEmpty) {
      final decoded = decodeApiRoutePolyline(encoded);
      if (decoded != null) {
        points = decoded;
        usedDecoded = decoded.length >= 2;
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
        usedDecoded = false;
      } else {
        final list = direction == _RouteDirection.goingTo
            ? route.goingTo
            : route.goingBack;
        if (list.length < 2) {
          final result = (
            points: const <LatLng>[],
            usedDecoded: false,
            usedValhalla: false,
          );
          _resolvedDirectionGeometryCache[cacheKey] = result;
          return result;
        }
        final sorted = List.of(list)
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
        points = sorted.map((p) => LatLng(p.lat, p.lon)).toList();
        usedDecoded = false;
        usedValhalla = false;
      }
    }

    if (points.length < 2) {
      final result = (
        points: const <LatLng>[],
        usedDecoded: false,
        usedValhalla: false,
      );
      _resolvedDirectionGeometryCache[cacheKey] = result;
      return result;
    }
    final result = (
      points: points,
      usedDecoded: usedDecoded,
      usedValhalla: usedValhalla,
    );
    _resolvedDirectionGeometryCache[cacheKey] = result;
    return result;
  }

  List<LatLng> _collectFitPointsForRoute(JeepneyRoute route) {
    final points = <LatLng>[];
    for (final direction in _RouteDirection.values) {
      final g = _resolveDirectionGeometry(route, direction);
      if (g.points.length >= 2) {
        points.addAll(g.points);
      }
    }
    if (points.isNotEmpty) return points;
    for (final p in route.goingTo) {
      points.add(LatLng(p.lat, p.lon));
    }
    for (final p in route.goingBack) {
      points.add(LatLng(p.lat, p.lon));
    }
    return points;
  }

  List<RouteHitPolyline> _buildHitTestPolylines() {
    final routes = _mapData?.routes ?? const <JeepneyRoute>[];
    final out = <RouteHitPolyline>[];
    for (final route in routes) {
      for (final direction in _RouteDirection.values) {
        final g = _resolveDirectionGeometry(route, direction);
        if (g.points.length >= 2) {
          out.add(RouteHitPolyline(routeId: route.id, points: g.points));
        }
      }
    }
    return out;
  }

  List<RouteHitPolyline> get _hitTestPolylines {
    if (_hitTestPolylineCache != null &&
        _hitTestPolylineCacheAtGeneration == _hitGeometryGeneration) {
      return _hitTestPolylineCache!;
    }
    final built = _buildHitTestPolylines();
    _hitTestPolylineCache = built;
    _hitTestPolylineCacheAtGeneration = _hitGeometryGeneration;
    return built;
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
        final g = _resolveDirectionGeometry(route, direction);
        if (g.points.length < 2) continue;
        final points = g.points;
        final usedDecoded = g.usedDecoded;
        final usedValhalla = g.usedValhalla;
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
    if (!_isFocusedMode) return routes;
    if (_selectedRouteIdsReadOnly.isEmpty) return const <JeepneyRoute>[];
    return routes.where((r) => _selectedRouteIdsReadOnly.contains(r.id)).toList();
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

  /// Centroid of ordered closure vertices (map label anchor).
  LatLng _closureLabelPoint(RoadClosure closure) {
    final ordered = closure.orderedPoints;
    var latSum = 0.0;
    var lngSum = 0.0;
    for (final p in ordered) {
      latSum += p.lat;
      lngSum += p.lng;
    }
    final n = ordered.length;
    return LatLng(latSum / n, lngSum / n);
  }

  /// Floating "Road Closure" chips above each polygon (tap opens in-drawer details).
  List<Marker> get _closureLabelMarkers {
    final closures = _mapData?.closures ?? const <RoadClosure>[];
    final markers = <Marker>[];
    for (final closure in closures) {
      if (!closure.canRenderPolygon) continue;
      markers.add(
        Marker(
          point: _closureLabelPoint(closure),
          width: 76,
          height: 20,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () => _openClosureDetails(closure),
            child: Material(
              elevation: 3,
              shadowColor: Colors.black38,
              borderRadius: BorderRadius.circular(6),
              color: MapColors.background,
              child: Container(
                width: 76,
                height: 20,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _closureColor, width: 1),
                ),
                child: const Text(
                  '❌ Road Closed',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MapColors.text,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  void _onClosureLayerHit() {
    if (!mounted) return;
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
    _openClosureDetails(selected);
  }

  void _openClosureDetails(RoadClosure closure) {
    if (!mounted) return;
    setState(() {
      _selectedClosureForDetails = closure;
      _showingClosureDetails = true;
      _showingRouteDetails = false;
      _selectedRouteForDetails = null;
      _showingOverlappingRoutes = false;
      _overlappingRoutes = const <JeepneyRoute>[];
      _returnToOverlappingRoutesAfterDetails = false;
    });
  }

  void _closeClosureDetails() {
    setState(() {
      _showingClosureDetails = false;
      _selectedClosureForDetails = null;
    });
  }

  void _onRouteTap(JeepneyRoute route) {
    late List<JeepneyRoute> routesToFit;
    setState(() {
      if (!_isFocusedMode) {
        _isFocusedMode = true;
        _selectedRouteIds = <String>{route.id};
      } else if (_isCompareMode) {
        final selectedRouteIds = _selectedRouteIdsMutable();
        if (selectedRouteIds.contains(route.id)) {
          selectedRouteIds.remove(route.id);
        } else {
          selectedRouteIds.add(route.id);
        }
      } else {
        _selectedRouteIds = <String>{route.id};
      }
      routesToFit = _isFocusedMode
          ? _visibleRoutes
          : (_mapData?.routes ?? const <JeepneyRoute>[]);
    });

    if (routesToFit.isEmpty) {
      _mapController.move(_iloiloCenter, _initialZoom);
      return;
    }
    _fitRoutesBounds(routesToFit);
  }

  void _setMultiSelectMode(bool enabled) {
    if (_isCompareMode == enabled) return;

    late List<JeepneyRoute> routesToFit;
    setState(() {
      _isCompareMode = enabled;
      if (_isFocusedMode && !_isCompareMode && _selectedRouteIds != null) {
        final selectedRouteIds = _selectedRouteIdsMutable();
        if (selectedRouteIds.length > 1) {
          final retainedRouteId = selectedRouteIds.last;
          _selectedRouteIds = <String>{retainedRouteId};
        }
      }
      routesToFit = _isFocusedMode
          ? _visibleRoutes
          : (_mapData?.routes ?? const <JeepneyRoute>[]);
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
      _isFocusedMode = false;
      _selectedRouteIdsMutable()
        ..clear()
        ..addAll(allIds);
    });
    _fitRoutesBounds(allRoutes);
  }

  void _openRouteDetails(JeepneyRoute route) {
    setState(() {
      _selectedRouteForDetails = route;
      _showingRouteDetails = true;
      _showingClosureDetails = false;
      _selectedClosureForDetails = null;
      _showingOverlappingRoutes = false;
      _overlappingRoutes = const <JeepneyRoute>[];
      _returnToOverlappingRoutesAfterDetails = false;
    });
  }

  void _closeRouteDetails() {
    final resumeOverlap = _returnToOverlappingRoutesAfterDetails &&
        _overlappingRoutes.isNotEmpty;
    setState(() {
      _showingRouteDetails = false;
      _selectedRouteForDetails = null;
      if (resumeOverlap) {
        _returnToOverlappingRoutesAfterDetails = false;
        _showingOverlappingRoutes = true;
        _selectedRouteIdsMutable()
          ..clear()
          ..addAll(_overlappingRoutes.map((r) => r.id));
      } else {
        _returnToOverlappingRoutesAfterDetails = false;
      }
    });
    if (resumeOverlap) {
      _fitRoutesBounds(_overlappingRoutes);
    }
  }

  /// Fits map camera to route geometry (decoded/Valhalla polylines when present).
  void _fitRoutesBounds(List<JeepneyRoute> routes) {
    final points = <LatLng>[];
    for (final route in routes) {
      points.addAll(_collectFitPointsForRoute(route));
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

  void _onMapTapForOverlappingRoutes(TapPosition tapPosition, LatLng point) {
    if (_loadingRoutes) return;
    final cam = _mapController.camera;
    final rawThreshold = _overlapTapRadiusLogicalPixels *
        metersPerPixelAtLatitude(point.latitude, cam.zoom);
    final threshold = rawThreshold.clamp(
      _overlapThresholdMetersMin,
      _overlapThresholdMetersMax,
    );
    final matchIds = routeIdsNearPolylines(point, _hitTestPolylines, threshold);

    _mapController.move(point, math.max(cam.zoom, _overlapTapMinZoom));

    if (matchIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No routes near this point.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final allRoutes = _mapData?.routes ?? const <JeepneyRoute>[];
    final matched = allRoutes.where((r) => matchIds.contains(r.id)).toList()
      ..sort(_compareRouteNumbersAsc);

    setState(() {
      _showingOverlappingRoutes = true;
      _overlappingRoutes = matched;
      _showingClosureDetails = false;
      _selectedClosureForDetails = null;
      _showingRouteDetails = false;
      _selectedRouteForDetails = null;
      _returnToOverlappingRoutesAfterDetails = false;
    });
  }

  void _closeOverlappingRoutes() {
    setState(() {
      _showingOverlappingRoutes = false;
      _overlappingRoutes = const <JeepneyRoute>[];
      _returnToOverlappingRoutesAfterDetails = false;
    });
  }

  void _openRouteFromOverlap(JeepneyRoute route) {
    setState(() {
      _selectedRouteIdsMutable()
        ..clear()
        ..add(route.id);
      _showingOverlappingRoutes = false;
      _selectedRouteForDetails = route;
      _showingRouteDetails = true;
      _showingClosureDetails = false;
      _selectedClosureForDetails = null;
      _returnToOverlappingRoutesAfterDetails = true;
    });
    _fitRoutesBounds([route]);
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
                  child: _selectedNavIndex == 3
                      ? SettingsScreen(key: const ValueKey<String>('settings-screen'))
                      : _showingClosureDetails
                      ? _buildClosureDetailsView(scrollController)
                      : _showingRouteDetails
                      ? _buildRouteDetailsView(scrollController)
                      : _showingOverlappingRoutes
                      ? _buildOverlappingRoutesView(scrollController)
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
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilterChip(
              label: const Text('All routes'),
              selected: !_isFocusedMode,
              onSelected: (selected) {
                if (selected) {
                  _showAllRoutes();
                }
              },
              showCheckmark: false,
              selectedColor: MapColors.primary.withValues(alpha: 0.18),
              checkmarkColor: MapColors.primary,
              labelStyle: TextStyle(
                color: !_isFocusedMode
                    ? MapColors.primary
                    : MapColors.text.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: !_isFocusedMode
                    ? MapColors.primary.withValues(alpha: 0.7)
                    : MapColors.text.withValues(alpha: 0.18),
              ),
            ),
            FilterChip(
                  label: const Text('Compare Routes'),
                  selected: _isCompareMode,
                  onSelected: (selected) {
                    _setMultiSelectMode(selected);
                  },
                  showCheckmark: false,
                  selectedColor: MapColors.accentColor.withValues(alpha: 0.18),
                  checkmarkColor: MapColors.accentColor,
                  labelStyle: TextStyle(
                    color: _isCompareMode
                        ? MapColors.accentColor
                        : MapColors.text.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: _isCompareMode
                        ? MapColors.accentColor.withValues(alpha: 0.7)
                        : MapColors.text.withValues(alpha: 0.18),
                  ),
                ),
                FilterChip(
              label: const Text('Tricycle Stations'),
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

    final selectedRoutes = (_isFocusedMode && _isCompareMode)
      ? routes
        .where((route) => _selectedRouteIdsReadOnly.contains(route.id))
        .toList()
        : const <JeepneyRoute>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isFocusedMode && _isCompareMode) ...[
          const Text(
            'Selected Routes',
            style: TextStyle(
              color: MapColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (selectedRoutes.isEmpty)
            Text(
              'No routes selected.',
              style: TextStyle(
                color: MapColors.text.withValues(alpha: 0.65),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final route in selectedRoutes)
                  FilterChip(
                    label: Text(
                      route.routeNumber.trim().isEmpty
                          ? route.routeName
                          : route.routeNumber.trim(),
                    ),
                    selected: true,
                    onSelected: (_) => _onRouteTap(route),
                    showCheckmark: true,
                    selectedColor:
                        _parseRouteColor(route.routeColor).withValues(alpha: 0.18),
                    checkmarkColor: _parseRouteColor(route.routeColor),
                    labelStyle: TextStyle(
                      color: _parseRouteColor(route.routeColor),
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: _parseRouteColor(route.routeColor).withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
        ],
        const Text(
          'All Routes',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (int index = 0; index < routes.length; index++) ...[
          _buildRouteListItem(
            routes[index],
            isSelected:
                _isFocusedMode && _selectedRouteIdsReadOnly.contains(routes[index].id),
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

  /// Padding so ink/hover fully covers icon + label on web/desktop.
  Widget _buildDetailsBackButton({required VoidCallback onPressed}) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: MapColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: const Icon(Icons.arrow_back, size: 16),
      label: const Text('Back', style: TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _buildOverlappingRoutesView(ScrollController scrollController) {
    final routes = _overlappingRoutes;
    return ListView(
      key: const ValueKey<String>('overlapping-routes-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'Overlapping Routes',
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
            _buildDetailsBackButton(onPressed: _closeOverlappingRoutes),
          ],
        ),
        const SizedBox(height: 16),
        if (routes.isEmpty)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MapColors.primary.withValues(alpha: 0.18),
              ),
              color: MapColors.background,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: const Text(
              'No overlapping routes for this tap.',
              style: TextStyle(
                color: MapColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          Column(
            children: [
              for (int index = 0; index < routes.length; index++) ...[
                _buildRouteListItem(
                  routes[index],
                  isSelected: _selectedRouteIdsReadOnly.contains(routes[index].id),
                  overlapMode: true,
                ),
                if (index < routes.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
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
            _buildDetailsBackButton(onPressed: _closeRouteDetails),
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

  Widget _buildClosureDetailsView(ScrollController scrollController) {
    final closure = _selectedClosureForDetails;
    final title = (closure != null && closure.closureName.trim().isNotEmpty)
        ? closure.closureName.trim()
        : '(untitled)';
    final detailText =
        (closure != null && closure.closureDescription.trim().isNotEmpty)
        ? closure.closureDescription.trim()
        : 'No description available.';

    return ListView(
      key: const ValueKey<String>('closure-details-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  title,
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
            _buildDetailsBackButton(onPressed: _closeClosureDetails),
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

  Widget _buildRouteListItem(
    JeepneyRoute route, {
    required bool isSelected,
    bool overlapMode = false,
  }) {
    final color = _parseRouteColor(route.routeColor);
    final routeNumber = route.routeNumber.trim().isEmpty
        ? '--'
        : route.routeNumber.trim();

    void openFromOverlap() => _openRouteFromOverlap(route);

    return InkWell(
      onTap: overlapMode ? openFromOverlap : () => _onRouteTap(route),
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
            if (!overlapMode)
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

    if (index == 3) return;

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
