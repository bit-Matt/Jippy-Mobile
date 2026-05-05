import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/screens/routes_screen/widgets/closure_details_view.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/bottom_drawer.dart';
import 'package:jippy_mobile/screens/routes_screen/routes_state.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/loading_overlay.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/location_message.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/routes_canvas.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/routes_action_buttons.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/overlapping_routes_view.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/route_details_view.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/routes_header.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/routes_list_view.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/routes_loading_state.dart';
import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/data/map_data_loader.dart';
import 'package:jippy_mobile/data/valhalla_route_client.dart';
import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/models/road_closure.dart';
import 'package:jippy_mobile/models/routes_and_stations_data.dart';
import 'package:jippy_mobile/services/location_service.dart';
import 'package:jippy_mobile/utils/polyline_1e6.dart';
import 'package:jippy_mobile/utils/route_color_parser.dart';
import 'package:jippy_mobile/utils/route_polyline_hit.dart';
import 'package:jippy_mobile/utils/route_sort.dart';

/// Default center for the routes map: Iloilo City, Philippines.
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

/// Debug-only diagnostics for route polylines (decoded vs fallback).
const bool _debugPolylineDiagnostics = kDebugMode;

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

/// After a routes map tap for overlap, ensure at least this zoom when nudging the camera.
const double _overlapTapMinZoom = 15;

/// Full-screen routes map with OpenStreetMap tiles, user location dot, and structure for
/// static route polylines and A* path segments.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService.instance;
  Position? _userPosition;
  StreamSubscription<Position>? _positionSubscription;
  LocationPermission? _locationPermission;
  bool _permissionChecked = false;

  /// Loaded routes and stations from API (or asset fallback).
  RoutesAndStationsData? _routesData;
  bool _isUsingFallbackRoutesData = false;

  /// Loaded vector style. When null, we fall back to raster OSM tiles.
  Style? _vectorStyle;

  /// True while routes are being fetched and during the first render pass.
  bool _loadingRoutes = true;

  /// Unified state for panel mode + route selection UI.
  RoutesUiState _uiState = const RoutesUiState();

  /// Routes-map tap overlap mode visualization state (routes-map-only overlay).
  LatLng? _overlapTapCenter;
  double? _overlapTapRadiusMeters;

  /// Bumps when route geometry used for hit-testing must be rebuilt.
  int _hitGeometryGeneration = 0;
  List<RouteHitPolyline>? _hitTestPolylineCache;
  int? _hitTestPolylineCacheAtGeneration;
  final Map<String, ({List<LatLng> points, bool usedDecoded, bool usedValhalla})>
      _resolvedDirectionGeometryCache = <String, ({List<LatLng> points, bool usedDecoded, bool usedValhalla})>{};
  int? _resolvedDirectionGeometryCacheAtGeneration;

  /// Road-aligned route points fetched from Valhalla (when API polylines missing).
  /// Key format: `${route.id}_goingTo` / `${route.id}_goingBack`.
  Map<String, List<LatLng>> _roadAlignedPointsByKey = <String, List<LatLng>>{};
  bool _hasAppliedInitialRouteFit = false;
  final LayerHitNotifier<String> _closureHitNotifier = ValueNotifier(null);

  /// Prevents log spam by only printing when the signature changes.
  String? _lastPolylineDiagnosticsSignature;

  void _setPanelMode(
    RoutesPanelMode mode, {
    JeepneyRoute? selectedRoute,
    bool clearSelectedRoute = false,
    RoadClosure? selectedClosure,
    bool clearSelectedClosure = false,
    List<JeepneyRoute>? overlappingRoutes,
    bool? returnToOverlappingRoutesAfterDetails,
  }) {
    _uiState = _uiState.copyWith(
      panelMode: mode,
      selectedRoute: selectedRoute,
      clearSelectedRoute: clearSelectedRoute,
      selectedClosure: selectedClosure,
      clearSelectedClosure: clearSelectedClosure,
      overlappingRoutes: overlappingRoutes,
      returnToOverlappingRoutesAfterDetails:
          returnToOverlappingRoutesAfterDetails,
    );
  }

  void _clearOverlapTapVisuals() {
    _overlapTapCenter = null;
    _overlapTapRadiusMeters = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _closureHitNotifier.addListener(_onClosureLayerHit);
    _loadVectorStyle();
    _initLocation();
    _loadRoutesData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadVectorStyle();
      _loadRoutesData();
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
  Future<void> _loadRoutesData() async {
    if (!mounted) return;
    setState(() {
      _loadingRoutes = true;
    });
    try {
      RoutesAndStationsData data;
      var usedFallbackData = false;
      try {
        data = await loadRoutesFromApi();
      } catch (_) {
        data = await loadSampleMapData();
        usedFallbackData = true;
      }
      if (mounted) {
        final incomingRouteIds = data.routes.map((r) => r.id).toSet();
        setState(() {
          _routesData = data;
          _isUsingFallbackRoutesData = usedFallbackData;
          _hitGeometryGeneration++;

          // Selection semantics:
          // - Show All mode keeps every route selected.
          // - Focused mode keeps the current selection set and drops missing IDs.
          // - Single-select focused mode collapses any stale multi-selection to one route.
          if (!_uiState.isFocusedMode || _uiState.selectedRouteIds.isEmpty) {
            _uiState = _uiState.copyWith(
              selectedRouteIds: Set<String>.from(incomingRouteIds),
            );
          } else {
            final nextIds = Set<String>.from(_uiState.selectedRouteIds)
              ..removeWhere((id) => !incomingRouteIds.contains(id));
            if (!_uiState.isCompareMode && nextIds.length > 1) {
              final retainedRouteId = nextIds.last;
              _uiState = _uiState.copyWith(selectedRouteIds: <String>{retainedRouteId});
            } else {
              _uiState = _uiState.copyWith(selectedRouteIds: nextIds);
            }
          }
        });
        _completeRouteLoadingAfterRender();
        _fitAllRoutesOnInitialLoad(data.routes);
        _fetchValhallaRoutesForData(data);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _routesData = const RoutesAndStationsData(
            routes: [],
            stations: [],
            closures: [],
          );
          _isUsingFallbackRoutesData = false;
          _uiState = _uiState.copyWith(selectedRouteIds: <String>{});
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
  Future<void> _fetchValhallaRoutesForData(
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
    final cachedPosition = _locationService.lastKnown;
    if (cachedPosition != null && mounted) {
      setState(() => _userPosition = cachedPosition);
    }

    final serviceEnabled = await _locationService.isServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _permissionChecked = true;
        _locationPermission = null; // service disabled
      });
      return;
    }

    final permission = await _locationService.requestPermission();

    setState(() {
      _permissionChecked = true;
      _locationPermission = permission;
    });

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final stream = _locationService.stream;
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
            child: Stack(
              children: [
                RoutesCanvas(
                  mapController: _mapController,
                  vectorStyle: vectorStyle,
                  initialCenter: _iloiloCenter,
                  initialZoom: _initialZoom,
                  onMapTap: _onMapTapForOverlappingRoutes,
                  routePolylines: _routePolylines,
                  showOverlapRadius:
                      _uiState.panelMode == RoutesPanelMode.overlap,
                  overlapTapCenter: _overlapTapCenter,
                  overlapTapRadiusMeters: _overlapTapRadiusMeters,
                  closurePolygons: _closurePolygons,
                  closureHitNotifier: _closureHitNotifier,
                  closureLabelMarkers: _closureLabelMarkers,
                  stationMarkers: _stationMarkers,
                  showStations: _uiState.showStations,
                  userPosition: _userPosition == null
                      ? null
                      : LatLng(_userPosition!.latitude, _userPosition!.longitude),
                  osmTileUrl: _osmTileUrl,
                  userAgentPackageName: _userAgentPackageName,
                ),
                if (_loadingRoutes) const LoadingOverlay(),
              ],
            ),
          ),
          RoutesActionButtons(
            userPosition: _userPosition,
            mapController: _mapController,
          ),
          MapBottomDrawer(
            showingClosureDetails:
                _uiState.panelMode == RoutesPanelMode.closureDetails,
            showingRouteDetails:
                _uiState.panelMode == RoutesPanelMode.routeDetails,
            showingOverlappingRoutes:
                _uiState.panelMode == RoutesPanelMode.overlap,
            closureDetailsViewBuilder: (scrollController) => ClosureDetailsView(
              scrollController: scrollController,
              closure: _uiState.selectedClosure,
              onBackPressed: _closeClosureDetails,
            ),
            routeDetailsViewBuilder: (scrollController) => RouteDetailsView(
              scrollController: scrollController,
              route: _uiState.selectedRoute,
              onBackPressed: _closeRouteDetails,
            ),
            overlappingRoutesViewBuilder: (scrollController) =>
                OverlappingRoutesView(
                  scrollController: scrollController,
                  routes: _uiState.overlappingRoutes,
                  selectedRouteIds: _uiState.selectedRouteIds,
                  onBackPressed: _closeOverlappingRoutes,
                  onRouteTap: _openRouteFromOverlap,
                ),
            routesListViewBuilder: (scrollController) => RoutesListView(
              scrollController: scrollController,
              header: RoutesHeader(
                isFocusedMode: _uiState.isFocusedMode,
                isCompareMode: _uiState.isCompareMode,
                showStations: _uiState.showStations,
                onShowAllRoutes: _showAllRoutes,
                onCompareModeChanged: _setMultiSelectMode,
                onShowStationsChanged: (selected) {
                  setState(() {
                    _uiState = _uiState.copyWith(showStations: selected);
                  });
                },
              ),
              body: RoutesListBody(
                routes: _sortedRoutes,
                isLoading: _loadingRoutes,
                isFocusedMode: _uiState.isFocusedMode,
                isCompareMode: _uiState.isCompareMode,
                selectedRouteIds: _uiState.selectedRouteIds,
                onRouteTap: _onRouteTap,
                onRouteDetailsTap: _openRouteDetails,
                loadingState: const RoutesLoadingState(),
              ),
            ),
          ),
          if (_permissionChecked &&
              (_locationPermission == LocationPermission.denied ||
                  _locationPermission == LocationPermission.deniedForever ||
                  _locationPermission == null))
            MapLocationMessage(
              message: _locationPermission == null
                  ? 'Location service is disabled.'
                  : 'Location permission denied. Enable it to see your position on the routes map.',
            ),
        ],
      ),
    );
  }

  /// Shared resolution for drawing, camera fit, and routes-map tap hit testing.
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
    final routes = _routesData?.routes ?? const <JeepneyRoute>[];
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
      final routeColor = parseRouteColor(route.routeColor);
      for (final direction in _RouteDirection.values) {
        final g = _resolveDirectionGeometry(route, direction);
        if (g.points.length < 2) continue;
        final points = g.points;
        final usedDecoded = g.usedDecoded;
        final usedValhalla = g.usedValhalla;
        final shouldUseOfflineTranslucency = _isUsingFallbackRoutesData;
        if (_debugPolylineDiagnostics) {
          final dirLabel = direction == _RouteDirection.goingTo ? 'to' : 'back';
          diagParts.add(
            '${route.id}:$dirLabel:${usedDecoded ? 'decoded' : (usedValhalla ? 'valhalla' : 'fallback')}:${points.length}',
          );
        }
        polylines.add(
          Polyline<Object>(
            points: points,
            color: shouldUseOfflineTranslucency
                ? routeColor.withValues(alpha: 0.35)
                : usedDecoded || usedValhalla
                ? routeColor
                : routeColor.withValues(
                    alpha: 0.35,
                  ), // visually obvious fallback
            strokeWidth: shouldUseOfflineTranslucency
                ? (MapColors.jeepneyRouteStrokeWidth - 1).clamp(1, 999).toDouble()
                : usedDecoded || usedValhalla
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
    final routes = _routesData?.routes ?? const <JeepneyRoute>[];
    if (!_uiState.isFocusedMode) return routes;
    if (_uiState.selectedRouteIds.isEmpty) return const <JeepneyRoute>[];
    return routes.where((r) => _uiState.selectedRouteIds.contains(r.id)).toList();
  }

  List<Polygon<Object>> get _closurePolygons {
    final closures = _routesData?.closures ?? const [];
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

  /// Centroid of ordered closure vertices (routes-map label anchor).
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
    final closures = _routesData?.closures ?? const <RoadClosure>[];
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

    final closures = _routesData?.closures ?? const <RoadClosure>[];
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
      _setPanelMode(
        RoutesPanelMode.closureDetails,
        selectedClosure: closure,
        clearSelectedRoute: true,
        overlappingRoutes: const <JeepneyRoute>[],
        returnToOverlappingRoutesAfterDetails: false,
      );
    });
  }

  void _closeClosureDetails() {
    setState(() {
      _setPanelMode(RoutesPanelMode.routes, clearSelectedClosure: true);
    });
  }

  void _onRouteTap(JeepneyRoute route) {
    late List<JeepneyRoute> routesToFit;
    setState(() {
      if (!_uiState.isFocusedMode) {
        _uiState = _uiState.copyWith(
          isFocusedMode: true,
          selectedRouteIds: <String>{route.id},
        );
      } else if (_uiState.isCompareMode) {
        final selectedRouteIds = Set<String>.from(_uiState.selectedRouteIds);
        if (selectedRouteIds.contains(route.id)) {
          selectedRouteIds.remove(route.id);
        } else {
          selectedRouteIds.add(route.id);
        }
        _uiState = _uiState.copyWith(selectedRouteIds: selectedRouteIds);
      } else {
        _uiState = _uiState.copyWith(selectedRouteIds: <String>{route.id});
      }
      routesToFit = _uiState.isFocusedMode
          ? _visibleRoutes
          : (_routesData?.routes ?? const <JeepneyRoute>[]);
    });

    if (routesToFit.isEmpty) {
      _mapController.move(_iloiloCenter, _initialZoom);
      return;
    }
    _fitRoutesBounds(routesToFit);
  }

  void _setMultiSelectMode(bool enabled) {
    if (_uiState.isCompareMode == enabled) return;

    late List<JeepneyRoute> routesToFit;
    setState(() {
      _uiState = _uiState.copyWith(isCompareMode: enabled);
      if (_uiState.isFocusedMode && !_uiState.isCompareMode) {
        final selectedRouteIds = Set<String>.from(_uiState.selectedRouteIds);
        if (selectedRouteIds.length > 1) {
          final retainedRouteId = selectedRouteIds.last;
          _uiState = _uiState.copyWith(selectedRouteIds: <String>{retainedRouteId});
        }
      }
      routesToFit = _uiState.isFocusedMode
          ? _visibleRoutes
          : (_routesData?.routes ?? const <JeepneyRoute>[]);
    });

    if (routesToFit.isEmpty) {
      _mapController.move(_iloiloCenter, _initialZoom);
      return;
    }
    _fitRoutesBounds(routesToFit);
  }

  void _showAllRoutes() {
    final allRoutes = _routesData?.routes ?? const <JeepneyRoute>[];
    final allIds = allRoutes.map((r) => r.id).toSet();
    setState(() {
      _uiState = _uiState.copyWith(
        isFocusedMode: false,
        selectedRouteIds: allIds,
      );
    });
    _fitRoutesBounds(allRoutes);
  }

  void _openRouteDetails(JeepneyRoute route) {
    setState(() {
      _setPanelMode(
        RoutesPanelMode.routeDetails,
        selectedRoute: route,
        clearSelectedClosure: true,
        overlappingRoutes: const <JeepneyRoute>[],
        returnToOverlappingRoutesAfterDetails: false,
      );
    });
  }

  void _closeRouteDetails() {
    final allRoutes = _routesData?.routes ?? const <JeepneyRoute>[];
    final allIds = allRoutes.map((r) => r.id).toSet();
    setState(() {
      _setPanelMode(
        RoutesPanelMode.routes,
        clearSelectedRoute: true,
        overlappingRoutes: const <JeepneyRoute>[],
        returnToOverlappingRoutesAfterDetails: false,
      );
      _uiState = _uiState.copyWith(
        isFocusedMode: false,
        selectedRouteIds: allIds,
      );
      _clearOverlapTapVisuals();
    });
    _fitRoutesBounds(allRoutes);
  }

  /// Fits routes-map camera to route geometry (decoded/Valhalla polylines when present).
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
    final distanceByRoute = <String, double>{};
    for (final pl in _hitTestPolylines) {
      if (pl.points.length < 2) continue;
      final distance = minDistanceMetersPointToPolyline(point, pl.points);
      final current = distanceByRoute[pl.routeId];
      if (current == null || distance < current) {
        distanceByRoute[pl.routeId] = distance;
      }
    }
    final nearEntries = distanceByRoute.entries
        .where((entry) => entry.value <= threshold)
        .toList();

    _mapController.move(point, math.max(cam.zoom, _overlapTapMinZoom));

    if (nearEntries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No routes near this point.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    var minDistance = nearEntries.first.value;
    for (final entry in nearEntries.skip(1)) {
      if (entry.value < minDistance) minDistance = entry.value;
    }
    final exactTolerance = math.min(12.0, threshold * 0.35);
    final exactIds = <String>{
      for (final entry in nearEntries)
        if (entry.value <= minDistance + exactTolerance) entry.key,
    };

    final allRoutes = _routesData?.routes ?? const <JeepneyRoute>[];
    final matched = allRoutes.where((r) => exactIds.contains(r.id)).toList()
      ..sort(compareRouteNumbersAsc);

    if (matched.length == 1) {
      _openRouteFromMapTap(matched.first);
      return;
    }

    setState(() {
      _setPanelMode(
        RoutesPanelMode.overlap,
        overlappingRoutes: matched,
        clearSelectedClosure: true,
        clearSelectedRoute: true,
        returnToOverlappingRoutesAfterDetails: false,
      );
      _overlapTapCenter = point;
      _overlapTapRadiusMeters = threshold.toDouble();
    });
  }

  void _closeOverlappingRoutes() {
    setState(() {
      _setPanelMode(
        RoutesPanelMode.routes,
        overlappingRoutes: const <JeepneyRoute>[],
        returnToOverlappingRoutesAfterDetails: false,
      );
      _clearOverlapTapVisuals();
    });
  }

  void _openRouteFromOverlap(JeepneyRoute route) {
    setState(() {
      // When picking from overlap list, isolate the selected route on routes map.
      _setPanelMode(
        RoutesPanelMode.routeDetails,
        selectedRoute: route,
        clearSelectedClosure: true,
        returnToOverlappingRoutesAfterDetails: true,
      );
      _uiState = _uiState.copyWith(
        isFocusedMode: true,
        selectedRouteIds: <String>{route.id},
      );
      _clearOverlapTapVisuals();
    });
    _fitRoutesBounds([route]);
  }

  void _openRouteFromMapTap(JeepneyRoute route) {
    setState(() {
      _setPanelMode(
        RoutesPanelMode.routeDetails,
        selectedRoute: route,
        clearSelectedClosure: true,
        overlappingRoutes: const <JeepneyRoute>[],
        returnToOverlappingRoutesAfterDetails: false,
      );
      _uiState = _uiState.copyWith(
        isFocusedMode: true,
        selectedRouteIds: <String>{route.id},
      );
      _clearOverlapTapVisuals();
    });
    _fitRoutesBounds([route]);
  }

  /// Tricycle station markers (white circle, purple border, tricycle icon).
  List<Marker> get _stationMarkers {
    final stations = _routesData?.stations ?? [];
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

  List<JeepneyRoute> get _sortedRoutes {
    final routes = List<JeepneyRoute>.from(
      _routesData?.routes ?? const <JeepneyRoute>[],
    )..sort(compareRouteNumbersAsc);
    return routes;
  }

}
