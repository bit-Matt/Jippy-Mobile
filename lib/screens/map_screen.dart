import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/screens/map/widgets/closure_details_view.dart';
import 'package:jippy_mobile/screens/map/widgets/bottom_drawer.dart';
import 'package:jippy_mobile/screens/map/widgets/loading_overlay.dart';
import 'package:jippy_mobile/screens/map/widgets/location_message.dart';
import 'package:jippy_mobile/screens/map/widgets/map_action_buttons.dart';
import 'package:jippy_mobile/screens/map/widgets/overlapping_routes_view.dart';
import 'package:jippy_mobile/screens/map/widgets/route_details_view.dart';
import 'package:jippy_mobile/screens/map/widgets/routes_header.dart';
import 'package:jippy_mobile/screens/map/widgets/routes_list_view.dart';
import 'package:jippy_mobile/screens/map/widgets/routes_loading_state.dart';
import 'package:jippy_mobile/screens/map/widgets/search_bar_overlay.dart';

import '../core/theme/map_colors.dart';
import '../data/map_data_loader.dart';
import '../data/valhalla_route_client.dart';
import '../models/jeepney_route.dart';
import '../models/road_closure.dart';
import '../models/routes_and_stations_data.dart';
import '../utils/polyline_1e6.dart';
import '../utils/route_color_parser.dart';
import '../utils/route_polyline_hit.dart';
import '../utils/route_sort.dart';

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

  /// Loaded routes and stations from API (or asset fallback).
  RoutesAndStationsData? _mapData;
  bool _isUsingFallbackMapData = false;

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
  LatLng? _overlapTapCenter;
  double? _overlapTapRadiusMeters;

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
          _mapData = data;
          _isUsingFallbackMapData = usedFallbackData;
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
          _isUsingFallbackMapData = false;
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
            child: Stack(
              children: [
                FlutterMap(
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
                    if (_showingOverlappingRoutes &&
                        _overlapTapCenter != null &&
                        _overlapTapRadiusMeters != null)
                      CircleLayer(
                        circles: [
                          CircleMarker<Object>(
                            point: _overlapTapCenter!,
                            useRadiusInMeter: true,
                            radius: _overlapTapRadiusMeters!,
                            color: MapColors.primary.withValues(alpha: 0.14),
                            borderColor: MapColors.primary.withValues(alpha: 0.5),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
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
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
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
                if (_loadingRoutes) const LoadingOverlay(),
              ],
            ),
          ),
          if (_showSearchBar) const SearchBarOverlay(),
          MapActionButtons(
            userPosition: _userPosition,
            mapController: _mapController,
          ),
          MapBottomDrawer(
            showingClosureDetails: _showingClosureDetails,
            showingRouteDetails: _showingRouteDetails,
            showingOverlappingRoutes: _showingOverlappingRoutes,
            closureDetailsViewBuilder: (scrollController) => ClosureDetailsView(
              scrollController: scrollController,
              closure: _selectedClosureForDetails,
              onBackPressed: _closeClosureDetails,
            ),
            routeDetailsViewBuilder: (scrollController) => RouteDetailsView(
              scrollController: scrollController,
              route: _selectedRouteForDetails,
              onBackPressed: _closeRouteDetails,
            ),
            overlappingRoutesViewBuilder: (scrollController) =>
                OverlappingRoutesView(
                  scrollController: scrollController,
                  routes: _overlappingRoutes,
                  selectedRouteIds: _selectedRouteIdsReadOnly,
                  onBackPressed: _closeOverlappingRoutes,
                  onRouteTap: _openRouteFromOverlap,
                ),
            routesListViewBuilder: (scrollController) => RoutesListView(
              scrollController: scrollController,
              header: RoutesHeader(
                isFocusedMode: _isFocusedMode,
                isCompareMode: _isCompareMode,
                showStations: _showStations,
                onShowAllRoutes: _showAllRoutes,
                onCompareModeChanged: _setMultiSelectMode,
                onShowStationsChanged: (selected) {
                  setState(() => _showStations = selected);
                },
              ),
              body: RoutesListBody(
                routes: _sortedRoutes,
                isLoading: _loadingRoutes,
                isFocusedMode: _isFocusedMode,
                isCompareMode: _isCompareMode,
                selectedRouteIds: _selectedRouteIdsReadOnly,
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
      final routeColor = parseRouteColor(route.routeColor);
      for (final direction in _RouteDirection.values) {
        final g = _resolveDirectionGeometry(route, direction);
        if (g.points.length < 2) continue;
        final points = g.points;
        final usedDecoded = g.usedDecoded;
        final usedValhalla = g.usedValhalla;
        final shouldUseOfflineTranslucency = _isUsingFallbackMapData;
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
    final allIds = (_mapData?.routes ?? const <JeepneyRoute>[])
        .map((r) => r.id)
        .toSet();
    setState(() {
      _showingRouteDetails = false;
      _selectedRouteForDetails = null;
      if (resumeOverlap) {
        _returnToOverlappingRoutesAfterDetails = false;
        _showingOverlappingRoutes = true;
        // Return to overlap-list context and unhide all routes on the map.
        _isFocusedMode = false;
        _selectedRouteIdsMutable()
          ..clear()
          ..addAll(allIds);
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
      ..sort(compareRouteNumbersAsc);

    setState(() {
      _showingOverlappingRoutes = true;
      _overlappingRoutes = matched;
      _overlapTapCenter = point;
      _overlapTapRadiusMeters = threshold.toDouble();
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
      _overlapTapCenter = null;
      _overlapTapRadiusMeters = null;
      _returnToOverlappingRoutesAfterDetails = false;
    });
  }

  void _openRouteFromOverlap(JeepneyRoute route) {
    setState(() {
      // When picking from overlap list, isolate the selected route on map.
      _isFocusedMode = true;
      _selectedRouteIdsMutable()
        ..clear()
        ..add(route.id);
      _showingOverlappingRoutes = false;
      _selectedRouteForDetails = route;
      _showingRouteDetails = true;
      _showingClosureDetails = false;
      _selectedClosureForDetails = null;
      _returnToOverlappingRoutesAfterDetails = true;
      _overlapTapCenter = null;
      _overlapTapRadiusMeters = null;
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

  List<JeepneyRoute> get _sortedRoutes {
    final routes = List<JeepneyRoute>.from(
      _mapData?.routes ?? const <JeepneyRoute>[],
    )..sort(compareRouteNumbersAsc);
    return routes;
  }

}
