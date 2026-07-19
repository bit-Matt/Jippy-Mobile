import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' hide Position;

import 'package:jippy_mobile/core/config/map_config.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/closure_details_view.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/bottom_drawer.dart';
import 'package:jippy_mobile/screens/routes_screen/routes_state.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/loading_overlay.dart';
import 'package:jippy_mobile/widgets/jippy_map_canvas.dart';
import 'package:jippy_mobile/widgets/map_location_control.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/overlapping_routes_view.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/route_details_view.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/routes_header.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/routes_list_view.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/routes_loading_state.dart';
import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/data/map_data_loader.dart';
import 'package:jippy_mobile/data/valhalla_route_client.dart';
import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/models/map_layer_models.dart';
import 'package:jippy_mobile/models/road_closure.dart';
import 'package:jippy_mobile/models/routes_and_stations_data.dart';
import 'package:jippy_mobile/models/offline_map_status.dart';
import 'package:jippy_mobile/services/connectivity_service.dart';
import 'package:jippy_mobile/services/location_service.dart';
import 'package:jippy_mobile/services/offline_map_service.dart';
import 'package:jippy_mobile/utils/map_coords.dart';
import 'package:jippy_mobile/utils/polyline_1e6.dart';
import 'package:jippy_mobile/utils/route_arrow_utils.dart';
import 'package:jippy_mobile/utils/route_color_parser.dart';
import 'package:jippy_mobile/utils/route_polyline_hit.dart';
import 'package:jippy_mobile/utils/route_sort.dart';
import 'package:jippy_mobile/widgets/tricycle_station_marker.dart';

enum _RouteDirection { goingTo, goingBack }

/// Zoom level for the routes default view (city-wide over Iloilo).
const double _initialZoom = 12.0;

/// Debug-only diagnostics for route polylines (decoded vs fallback).
const bool _debugPolylineDiagnostics = kDebugMode;

const Color _closureColor = Color(0xFFE81123);
const double _closureFillOpacity = 0.25;

/// Logical pixels around the tap treated as "near" a route (converted to meters
/// at tap latitude and zoom via [metersPerPixelAtLatitude]).
const double _overlapTapRadiusLogicalPixels = 38;

/// Clamp for overlap distance (meters): avoids tiny thresholds when zoomed in
/// and excessive matches when zoomed out.
const double _overlapThresholdMetersMin = 28;
const double _overlapThresholdMetersMax = 220;

/// After a routes map tap for overlap, ensure at least this zoom when nudging the camera.
const double _overlapTapMinZoom = 15;

const double _drawerCollapsedSize = 0.16;
const double _drawerDefaultSize = 0.38;
const double _drawerMaxSize = 0.85;
const List<double> _drawerSnapSizes = <double>[
  _drawerCollapsedSize,
  _drawerDefaultSize,
  _drawerMaxSize,
];

/// Full-screen routes map with MapLibre basemap, user location, route polylines.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen>
    with WidgetsBindingObserver {
  MapController? _mapController;
  final DraggableScrollableController _drawerController =
      DraggableScrollableController();
  final ValueNotifier<double> _drawerExtent =
      ValueNotifier<double>(_drawerDefaultSize);
  final LocationService _locationService = LocationService.instance;
  Position? _userPosition;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  LocationPermission? _locationPermission;
  bool _permissionChecked = false;
  bool _online = true;
  bool _hasOfflineRegion = false;
  double _cameraZoom = _initialZoom;

  /// Loaded routes and stations from API or offline cache.
  RoutesAndStationsData? _routesData;

  String? _mapStyle;
  bool _mapEverActive = false;

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
  final Map<
    String,
    ({List<LatLng> points, bool usedDecoded, bool usedValhalla})
  >
  _resolvedDirectionGeometryCache =
      <String, ({List<LatLng> points, bool usedDecoded, bool usedValhalla})>{};
  int? _resolvedDirectionGeometryCacheAtGeneration;

  /// Road-aligned route points fetched from Valhalla (when API polylines missing).
  /// Key format: `${route.id}_goingTo` / `${route.id}_goingBack`.
  Map<String, List<LatLng>> _roadAlignedPointsByKey = <String, List<LatLng>>{};
  bool _hasAppliedInitialRouteFit = false;

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

  void _moveToDefaultMapView() {
    final controller = _mapController;
    if (controller == null) return;
    controller.moveCamera(
      center: toGeographic(MapConfig.routesDefaultCenter),
      zoom: _initialZoom,
      padding: EdgeInsets.zero,
    );
    _cameraZoom = _initialZoom;
  }

  void _resetToDefaultView() {
    final allRoutes = _routesData?.routes ?? const <JeepneyRoute>[];
    final allIds = allRoutes.map((route) => route.id).toSet();

    setState(() {
      _uiState = RoutesUiState(selectedRouteIds: allIds);
      _clearOverlapTapVisuals();
    });

    _moveToDefaultMapView();
    _animateDrawerTo(_drawerDefaultSize);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapEverActive = widget.isActive;
    _online = ConnectivityService.instance.isOnline.value;
    ConnectivityService.instance.isOnline.addListener(_onConnectivityChanged);
    OfflineMapService.instance.status.addListener(_onOfflineMapStatusChanged);
    unawaited(_refreshOfflineRegionState());
    _resolveMapStyle();
    _initLocation();
    _subscribeToServiceStatus();
    _loadRoutesData();
  }

  @override
  void didUpdateWidget(RoutesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive) {
      _mapEverActive = true;
    }
    if (oldWidget.isActive && !widget.isActive) {
      _resetToDefaultView();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOfflineRegionState());
      _resolveMapStyle();
      _loadRoutesData();
      _locationService.refresh();
      _initLocation();
    }
  }

  void _subscribeToServiceStatus() {
    _serviceStatusSubscription = _locationService.serviceStatusStream.listen((
      ServiceStatus status,
    ) {
      if (!mounted) return;
      if (status == ServiceStatus.enabled) {
        _initLocation();
      } else if (status == ServiceStatus.disabled) {
        setState(() {
          _permissionChecked = true;
          _locationPermission = null;
          _userPosition = null;
        });
      }
    });
  }

  void _onConnectivityChanged() {
    final online = ConnectivityService.instance.isOnline.value;
    if (online == _online) return;
    setState(() => _online = online);
    unawaited(_resolveMapStyle());
    unawaited(_loadRoutesData());
  }

  void _onOfflineMapStatusChanged() {
    final status = OfflineMapService.instance.status.value;
    final hasRegion = status is OfflineMapDownloaded;
    if (hasRegion != _hasOfflineRegion) {
      setState(() => _hasOfflineRegion = hasRegion);
      unawaited(_resolveMapStyle());
    }
    if (status is OfflineMapDownloaded) {
      unawaited(_loadRoutesData());
    }
  }

  Future<void> _refreshOfflineRegionState() async {
    final hasRegion = await OfflineMapService.instance.hasDownloadedRegion();
    if (!mounted) return;
    if (hasRegion != _hasOfflineRegion) {
      setState(() => _hasOfflineRegion = hasRegion);
    }
  }

  Future<void> _resolveMapStyle() async {
    final online = ConnectivityService.instance.isOnline.value;
    final style = await resolveMapStyle(
      primaryStyleUrl: MapConfig.routesStyleUrl,
      online: online,
      hasOfflineRegion: _hasOfflineRegion,
    );
    if (!mounted) return;
    setState(() => _mapStyle = style);
  }

  JeepneyRoute? _routeById(String? id) {
    return _routeByIdFromList(_routesData?.routes ?? const <JeepneyRoute>[], id);
  }

  JeepneyRoute? _routeByIdFromList(List<JeepneyRoute> routes, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final route in routes) {
      if (route.id == id) return route;
    }
    return null;
  }

  /// Route details must read from [_routesData] so offline image paths stay current.
  JeepneyRoute? get _routeForDetails =>
      _routeById(_uiState.selectedRoute?.id) ?? _uiState.selectedRoute;

  void _onMapCreated(MapController controller) {
    _mapController = controller;
    _cameraZoom = controller.getCamera().zoom;
  }

  /// Loads routes from API; on failure falls back to asset data.
  Future<void> _loadRoutesData() async {
    if (!mounted) return;
    setState(() {
      _loadingRoutes = true;
    });
    try {
      final result = await loadMapDataForCurrentConnectivity();
      final data = result.data;
      if (mounted) {
        final incomingRouteIds = data.routes.map((r) => r.id).toSet();
        setState(() {
          _routesData = data;
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
              _uiState = _uiState.copyWith(
                selectedRouteIds: <String>{retainedRouteId},
              );
            } else {
              _uiState = _uiState.copyWith(selectedRouteIds: nextIds);
            }
          }

          final selectedId = _uiState.selectedRoute?.id;
          if (selectedId != null) {
            final refreshed = _routeByIdFromList(data.routes, selectedId);
            if (refreshed != null) {
              _uiState = _uiState.copyWith(selectedRoute: refreshed);
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
            regions: [],
            closures: [],
          );
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
      _moveToDefaultMapView();
    });
  }

  /// Fetches road-aligned geometry from Valhalla for each route direction; updates state on success.
  /// If the Valhalla status check fails, skips requests so routes stay as straight segments.
  Future<void> _fetchValhallaRoutesForData(RoutesAndStationsData data) async {
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
    if (cachedPosition != null && mounted && _userPosition == null) {
      setState(() => _userPosition = cachedPosition);
    }

    final serviceEnabled = await _locationService.isServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      setState(() {
        _permissionChecked = true;
        _locationPermission = null;
      });
      return;
    }

    final permission = await _locationService.requestPermission();
    if (!mounted) return;

    setState(() {
      _permissionChecked = true;
      _locationPermission = permission;
    });

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    if (_positionSubscription != null) {
      // Already subscribed; service was re-enabled or screen resumed.
      await _locationService.refresh();
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
    ConnectivityService.instance.isOnline.removeListener(_onConnectivityChanged);
    OfflineMapService.instance.status.removeListener(_onOfflineMapStatusChanged);
    _positionSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _drawerController.dispose();
    _drawerExtent.dispose();
    super.dispose();
  }

  bool get _locationOn {
    if (!_permissionChecked) return true;
    final permission = _locationPermission;
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  String get _locationOffMessage {
    if (_locationPermission == null) {
      return 'Location service is disabled.';
    }
    return 'Location permission denied. Enable it to see your position.';
  }

  Future<void> _enableLocation() async {
    if (_locationPermission == null) {
      await Geolocator.openLocationSettings();
      return;
    }
    if (_locationPermission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }
    await _initLocation();
  }

  void _recenterOnUser() {
    final position = _userPosition;
    final controller = _mapController;
    if (position == null || controller == null) return;
    controller.moveCamera(
      center: toGeographic(LatLng(position.latitude, position.longitude)),
      zoom: _cameraZoom,
      padding: EdgeInsets.zero,
    );
  }

  List<MapCircleSpec> get _overlapCircles {
    if (_uiState.panelMode != RoutesPanelMode.overlap ||
        _overlapTapCenter == null ||
        _overlapTapRadiusMeters == null) {
      return const [];
    }
    final controller = _mapController;
    final radiusMeters = _overlapTapRadiusMeters!;
    final radiusPixels = controller == null
        ? 40
        : (radiusMeters / controller.getMetersPerPixelAtLatitude(
            _overlapTapCenter!.latitude,
          )).round().clamp(8, 400);
    return [
      MapCircleSpec(
        point: _overlapTapCenter!,
        radiusPixels: radiusPixels,
        color: MapColors.primary.withValues(alpha: 0.14),
        strokeColor: MapColors.primary.withValues(alpha: 0.5),
        strokeWidth: 2,
      ),
    ];
  }

  List<MapWidgetMarkerSpec> get _overlapPinMarkers {
    if (_uiState.panelMode != RoutesPanelMode.overlap ||
        _overlapTapCenter == null) {
      return const [];
    }
    const pinSize = 34.0;
    return [
      MapWidgetMarkerSpec(
        point: _overlapTapCenter!,
        size: const Size(pinSize, pinSize),
        child: Icon(
          Icons.place_rounded,
          color: MapColors.secondary,
          size: pinSize,
          shadows: const [
            Shadow(color: Colors.white, blurRadius: 4),
            Shadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    ];
  }

  RoadClosure? _closureAtPoint(LatLng point) {
    for (final closure in _routesData?.closures ?? const <RoadClosure>[]) {
      if (!closure.canRenderPolygon) continue;
      final polygon = closure.orderedPoints
          .map((p) => LatLng(p.lat, p.lng))
          .toList(growable: false);
      if (pointInPolygon(point, polygon)) return closure;
    }
    return null;
  }

  void _handleMapTap(LatLng point) {
    final closure = _closureAtPoint(point);
    if (closure != null) {
      _openClosureDetails(closure);
      return;
    }
    _onMapTapForOverlappingRoutes(point);
  }

  @override
  Widget build(BuildContext context) {
    final mapStyle = _mapStyle;
    return Scaffold(
      body: NotificationListener<DraggableScrollableNotification>(
        onNotification: (notification) {
          _drawerExtent.value = notification.extent;
          return false;
        },
        child: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              children: [
                if (mapStyle != null && _mapEverActive)
                  JippyMapCanvas(
                    style: mapStyle,
                    initialCenter: MapConfig.routesDefaultCenter,
                    initialZoom: _initialZoom,
                    onMapCreated: _onMapCreated,
                    onMapClick: _handleMapTap,
                    polylines: _routePolylines,
                    polygons: _closurePolygons,
                    widgetMarkers: [
                      ..._arrowMarkers,
                      ..._closureLabelMarkers,
                      if (_uiState.showStations) ..._stationMarkers,
                      ..._overlapPinMarkers,
                    ],
                    circles: _overlapCircles,
                  )
                else
                  const ColoredBox(color: MapColors.mapCanvasPlaceholder),
                if (_loadingRoutes) const LoadingOverlay(),
              ],
            ),
          ),
          MapLocationControl(
            drawerExtent: _drawerExtent,
            followClampExtent: _drawerDefaultSize,
            locationOn: _locationOn,
            isFollowing: true,
            onRecenter: _recenterOnUser,
            onEnableLocation: _enableLocation,
            offMessage: _locationOffMessage,
          ),
          MapBottomDrawer(
            controller: _drawerController,
            initialChildSize: _drawerDefaultSize,
            minChildSize: _drawerCollapsedSize,
            maxChildSize: _drawerMaxSize,
            snapSizes: _drawerSnapSizes,
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
              route: _routeForDetails,
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
                isCompareMode: _uiState.isCompareMode,
                showStations: _uiState.showStations,
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
                onShowAllRoutes: _showAllRoutes,
                onRouteTap: _onRouteTap,
                onRouteDetailsTap: _openRouteDetails,
                loadingState: const RoutesLoadingState(),
              ),
            ),
          ),
        ],
        ),
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

  /// Direction arrows and polyline offset when 1–3 routes are selected.
  bool get _shouldShowArrows {
    if (!_uiState.isFocusedMode) return false;
    final count = _uiState.selectedRouteIds.length;
    return count >= 1 && count <= 3;
  }

  /// Gray route halos when the map shows a filtered subset of routes.
  bool get _shouldShowRouteOutlines =>
      _uiState.isFocusedMode ||
      _uiState.panelMode == RoutesPanelMode.overlap;

  List<LatLng> _displayPointsForDirection(List<LatLng> points) {
    if (!_shouldShowArrows || points.length < 2) return points;
    return offsetPolyline(points, routePolylineOffsetMeters);
  }

  /// Polylines to draw (jeepney routes: goingTo and goingBack).
  ///
  /// Prefers encoded polylines from the API (`polylineGoingTo` / `polylineGoingBack`).
  /// Falls back to straight segments between the stored waypoints.
  List<MapPolylineSpec> get _routePolylines {
    final routes = _visibleRoutes;
    final showOutline = _shouldShowRouteOutlines;
    final polylines = <MapPolylineSpec>[];
    final diagParts = <String>[];
    for (final route in routes) {
      final routeColor = parseRouteColor(route.routeColor);
      for (final direction in _RouteDirection.values) {
        final g = _resolveDirectionGeometry(route, direction);
        if (g.points.length < 2) continue;
        final points = _displayPointsForDirection(g.points);
        final usedDecoded = g.usedDecoded;
        final usedValhalla = g.usedValhalla;
        if (_debugPolylineDiagnostics) {
          final dirLabel = direction == _RouteDirection.goingTo ? 'to' : 'back';
          diagParts.add(
            '${route.id}:$dirLabel:${usedDecoded ? 'decoded' : (usedValhalla ? 'valhalla' : 'fallback')}:${points.length}',
          );
        }
        final width = usedDecoded || usedValhalla
            ? MapColors.jeepneyRouteStrokeWidth.round()
            : (MapColors.jeepneyRouteStrokeWidth - 1).clamp(1, 999).round();
        polylines.add(
          MapPolylineSpec(
            points: points,
            color: usedDecoded || usedValhalla
                ? routeColor
                : routeColor.withValues(alpha: 0.35),
            width: width,
            showOutline: showOutline,
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

  List<MapWidgetMarkerSpec> get _arrowMarkers {
    if (!_shouldShowArrows) return const <MapWidgetMarkerSpec>[];

    final markers = <MapWidgetMarkerSpec>[];
    for (final route in _visibleRoutes) {
      final routeColor = parseRouteColor(route.routeColor);
      for (final direction in _RouteDirection.values) {
        final g = _resolveDirectionGeometry(route, direction);
        if (g.points.length < 2) continue;
        final offsetPoints = _displayPointsForDirection(g.points);
        markers.addAll(buildArrowMarkers(offsetPoints, routeColor));
      }
    }
    return markers;
  }

  List<JeepneyRoute> get _visibleRoutes {
    final routes = _routesData?.routes ?? const <JeepneyRoute>[];
    if (_uiState.panelMode == RoutesPanelMode.overlap) {
      final overlap = _uiState.overlappingRoutes;
      if (overlap.isEmpty) return const <JeepneyRoute>[];
      final overlapIds = overlap.map((r) => r.id).toSet();
      return routes.where((r) => overlapIds.contains(r.id)).toList();
    }
    if (!_uiState.isFocusedMode) return routes;
    if (_uiState.selectedRouteIds.isEmpty) return const <JeepneyRoute>[];
    return routes
        .where((r) => _uiState.selectedRouteIds.contains(r.id))
        .toList();
  }

  List<MapPolygonSpec> get _closurePolygons {
    final closures = _routesData?.closures ?? const [];
    final polygons = <MapPolygonSpec>[];

    for (final closure in closures) {
      if (!closure.canRenderPolygon) continue;
      final ordered = closure.orderedPoints;

      final points = ordered.map((p) => LatLng(p.lat, p.lng)).toList();
      if (points.length < 3) continue;

      polygons.add(
        MapPolygonSpec(
          points: points,
          fillColor: _closureColor.withValues(alpha: _closureFillOpacity),
          outlineColor: _closureColor,
          id: closure.id,
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
  List<MapWidgetMarkerSpec> get _closureLabelMarkers {
    final closures = _routesData?.closures ?? const <RoadClosure>[];
    final markers = <MapWidgetMarkerSpec>[];
    for (final closure in closures) {
      if (!closure.canRenderPolygon) continue;
      markers.add(
        MapWidgetMarkerSpec(
          point: _closureLabelPoint(closure),
          size: const Size(76, 20),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () => _openClosureDetails(closure),
            child: Builder(
              builder: (context) {
                final colorScheme = Theme.of(context).colorScheme;
                return Material(
                  elevation: 3,
                  shadowColor: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                  color: colorScheme.surface,
                  child: Container(
                    width: 76,
                    height: 20,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _closureColor, width: 1),
                    ),
                    child: Text(
                      '❌ Road Closed',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    return markers;
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
      _moveToDefaultMapView();
      return;
    }
    _fitRoutesBounds(routesToFit);

    if (_uiState.isFocusedMode &&
        !_uiState.isCompareMode &&
        _uiState.selectedRouteIds.length == 1) {
      _snapDrawerToMiddle();
    }
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
          _uiState = _uiState.copyWith(
            selectedRouteIds: <String>{retainedRouteId},
          );
        }
      }
      routesToFit = _uiState.isFocusedMode
          ? _visibleRoutes
          : (_routesData?.routes ?? const <JeepneyRoute>[]);
    });

    if (routesToFit.isEmpty) {
      _moveToDefaultMapView();
    } else {
      _fitRoutesBounds(routesToFit);
    }

    if (enabled) {
      _animateDrawerTo(_drawerMaxSize);
    }
  }

  void _showAllRoutes() {
    final allRoutes = _routesData?.routes ?? const <JeepneyRoute>[];
    final allIds = allRoutes.map((r) => r.id).toSet();
    final wasCompareMode = _uiState.isCompareMode;
    setState(() {
      _uiState = _uiState.copyWith(
        isFocusedMode: false,
        isCompareMode: false,
        selectedRouteIds: allIds,
      );
    });
    _fitRoutesBounds(allRoutes);
    if (wasCompareMode) {
      _animateDrawerTo(_drawerDefaultSize);
    }
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
      _uiState = _uiState.copyWith(
        isFocusedMode: true,
        selectedRouteIds: <String>{route.id},
      );
      _clearOverlapTapVisuals();
    });
    _fitRoutesBounds([route]);
    _snapDrawerToMiddle();
  }

  void _closeRouteDetails() {
    final resumeOverlap =
        _uiState.returnToOverlappingRoutesAfterDetails &&
        _uiState.overlappingRoutes.isNotEmpty;
    final allRoutes = _routesData?.routes ?? const <JeepneyRoute>[];
    final allIds = allRoutes.map((r) => r.id).toSet();
    setState(() {
      if (resumeOverlap) {
        _setPanelMode(
          RoutesPanelMode.overlap,
          clearSelectedRoute: true,
          returnToOverlappingRoutesAfterDetails: false,
        );
      } else {
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
      }
    });
    if (resumeOverlap) {
      _fitRoutesBounds(_uiState.overlappingRoutes);
    } else {
      _fitRoutesBounds(allRoutes);
    }
    _expandDrawerToDefault();
  }

  /// Fits routes-map camera to route geometry (decoded/Valhalla polylines when present).
  Future<void> _fitRoutesBounds(List<JeepneyRoute> routes) async {
    final controller = _mapController;
    if (controller == null) return;
    final points = <LatLng>[];
    for (final route in routes) {
      points.addAll(_collectFitPointsForRoute(route));
    }

    if (points.isEmpty) {
      _moveToDefaultMapView();
      return;
    }

    try {
      await controller.fitBounds(
        bounds: toLngLatBounds(points),
        padding: const EdgeInsets.fromLTRB(32, 110, 32, 300),
        offset: Offset.zero,
      );
      _cameraZoom = controller.getCamera().zoom;
    } catch (_) {
      final center = toGeographic(
        LatLng(
          points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
          points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
        ),
      );
      await controller.moveCamera(center: center, zoom: _cameraZoom);
    }
  }

  void _onMapTapForOverlappingRoutes(LatLng point) {
    if (_loadingRoutes) return;
    final controller = _mapController;
    if (controller == null) return;
    final zoom = controller.getCamera().zoom;
    final rawThreshold =
        _overlapTapRadiusLogicalPixels *
        controller.getMetersPerPixelAtLatitude(point.latitude);
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

    unawaited(
      controller.moveCamera(
        center: toGeographic(point),
        zoom: math.max(zoom, _overlapTapMinZoom),
        padding: EdgeInsets.zero,
      ),
    );
    _cameraZoom = math.max(zoom, _overlapTapMinZoom);

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
    final allRoutes = _routesData?.routes ?? const <JeepneyRoute>[];
    final allIds = allRoutes.map((r) => r.id).toSet();
    setState(() {
      _setPanelMode(
        RoutesPanelMode.routes,
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
    _expandDrawerToDefault();
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
    _snapDrawerToMiddle();
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
    _snapDrawerToMiddle();
  }

  void _snapDrawerToMiddle() {
    _animateDrawerTo(_drawerDefaultSize);
  }

  void _expandDrawerToDefault() {
    _animateDrawerTo(_drawerDefaultSize);
  }

  void _animateDrawerTo(double size) {
    try {
      _drawerController.animateTo(
        size,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  /// Tricycle station markers (white circle, purple border, tricycle icon).
  List<MapWidgetMarkerSpec> get _stationMarkers {
    final stations = _routesData?.stations ?? [];
    return stations
        .map(
          (s) => buildTricycleStationMarker(
            point: LatLng(s.lat, s.lon),
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
