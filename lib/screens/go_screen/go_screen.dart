import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vibration/vibration.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/data/map_data_loader.dart';
import 'package:jippy_mobile/data/navigate_client.dart';
import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/models/navigate_suggestion.dart';
import 'package:jippy_mobile/screens/go_screen/go_state.dart';
import 'package:jippy_mobile/screens/go_screen/widgets/debug_trip_simulator_overlay.dart';
import 'package:jippy_mobile/screens/go_screen/widgets/go_map_canvas.dart';
import 'package:jippy_mobile/screens/go_screen/widgets/go_search_bar.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/location_message.dart';
import 'package:jippy_mobile/services/geocoding_service.dart';
import 'package:jippy_mobile/services/location_service.dart';
import 'package:jippy_mobile/services/navigation_tracker.dart';
import 'package:jippy_mobile/services/notification_service.dart';
import 'package:jippy_mobile/services/trip_simulator_service.dart';
import 'package:jippy_mobile/utils/polyline_1e6.dart';
import 'package:jippy_mobile/utils/route_color_parser.dart';
import 'package:jippy_mobile/widgets/sheet_scroll_hint.dart';
import 'package:jippy_mobile/widgets/sticker_gallery.dart';
import 'package:jippy_mobile/widgets/sheet_drag_handle.dart';

final LatLng _iloiloCenter = LatLng(10.7202, 122.5621);

const double _initialZoom = 14.0;
const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _vectorStyleUrl =
    'https://jippy.shinosawa-laboratories.dev/tileserver/liberty.json';
const String _userAgentPackageName = 'com.jippy.mobile';

const Color _sheetSurfaceColor = Colors.white;
const Color _timelineSubtleLineColor = Color(0xFFCFD4DB);
const double _routeProgressSnapMaxMeters = 50.0;

const double _sheetCollapsedSize = 0.25;
const double _sheetDefaultSize = 0.40;
const double _sheetMaxSize = 0.85;
const List<double> _sheetSnapSizes = <double>[
  _sheetCollapsedSize,
  _sheetDefaultSize,
  _sheetMaxSize,
];

/// Progress along the selected route: leg index, segment start point index, and
/// interpolation [t] in [0, 1] along that segment.
typedef RouteProgress = ({int legIndex, int pointIndex, double t});

bool _hasNetworkInterface(List<ConnectivityResult> results) {
  if (results.length == 1 && results.single == ConnectivityResult.none) {
    return false;
  }
  return true;
}

class GoScreen extends StatefulWidget {
  const GoScreen({
    super.key,
    this.isActive = true,
    this.onReady,
    this.onBottomNavVisibilityChanged,
  });

  final bool isActive;
  final VoidCallback? onReady;
  final ValueChanged<bool>? onBottomNavVisibilityChanged;

  @override
  State<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends State<GoScreen> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final GeocodingService _geocoding = GeocodingService();
  final LocationService _locationService = LocationService.instance;
  final Connectivity _connectivity = Connectivity();
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  final FocusNode _startFocus = FocusNode();
  final FocusNode _endFocus = FocusNode();

  Style? _vectorStyle;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  StreamSubscription<double?>? _headingSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<ProximityEvent>? _trackerSubscription;
  StreamSubscription<TripSimulatorState>? _simulatorStateSubscription;

  GoNavigationFlow _flow = GoNavigationFlow.explore;
  bool _bottomNavHidden = false;
  GoPinTarget? _pinTarget;
  GoRoutingField _activeRoutingField = GoRoutingField.end;

  LatLng? _start;
  LatLng? _end;
  LatLng? _selectedExplorePoint;
  String _selectedExploreLabel = '';

  List<NominatimSearchHit> _suggestions = const [];
  String? _searchError;
  bool _nominatimBusy = false;

  bool _routePreviewLoading = false;
  String? _routePreviewSignature;
  int _navigateRequestToken = 0;

  List<NavigateSuggestion> _routeSuggestions = const [];
  int _selectedSuggestionIndex = 0;
  int? _isolatedLegIndex;
  NavigationTracker? _navigationTracker;
  bool _navigationBusy = false;
  int _currentStopIndex = 0;
  TripSimulatorService? _tripSimulator;
  TripSimulatorState _tripSimulatorState = TripSimulatorState.idle;
  bool _debugTripSimulatorEnabled = false;
  DateTime? _lastProximityAlertAt;
  Offset _simOverlayOffset = const Offset(0, 120);

  Position? _userPosition;
  RouteProgress? _routeProgress;
  double? _compassHeading;
  LocationPermission? _locationPermission;
  bool _permissionChecked = false;
  bool _hasCenteredToUserOnce = false;
  bool _followUser = true;
  bool _suppressNextGestureFollowBreak = false;

  bool _online = true;
  Timer? _searchDebounce;

  Map<String, List<String>> _stickerUrlsByRouteId = const {};

  bool _readinessSignaled = false;
  bool _vectorStyleAttempted = false;
  bool _mapFirstFrame = false;
  bool _locationAttempted = false;

  bool get _gpsOriginAvailable {
    if (_userPosition == null) return false;
    final p = _locationPermission;
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  bool get _showRoutingHeader {
    return _flow == GoNavigationFlow.routingInput ||
        _flow == GoNavigationFlow.routeSelection ||
        _flow == GoNavigationFlow.routeDetails ||
        _flow == GoNavigationFlow.navigating;
  }

  GoSearchBarMode get _searchMode {
    return _showRoutingHeader
        ? GoSearchBarMode.expanded
        : GoSearchBarMode.collapsed;
  }

  bool get _destinationOutOfArea {
    final d = _end;
    if (d == null) return false;
    return !_geocoding.isWithinIloiloServiceArea(d);
  }

  NavigateSuggestion? get _selectedSuggestion {
    if (_routeSuggestions.isEmpty) return null;
    if (_selectedSuggestionIndex < 0 ||
        _selectedSuggestionIndex >= _routeSuggestions.length) {
      return _routeSuggestions.first;
    }
    return _routeSuggestions[_selectedSuggestionIndex];
  }

  LatLng? get _mapOrigin => _showRoutingHeader ? _start : null;

  LatLng? get _mapDestination {
    if (_flow == GoNavigationFlow.locationDetail) return _selectedExplorePoint;
    if (_showRoutingHeader) return _end;
    return null;
  }

  int? get _activeLegIsolationIndex {
    final isolated = switch (_flow) {
      GoNavigationFlow.routeDetails => _isolatedLegIndex,
      _ => null,
    };
    if (isolated == null) return null;

    final selected = _selectedSuggestion;
    if (selected == null) return null;
    if (isolated < 0 || isolated >= selected.route.legs.length) {
      return null;
    }

    return isolated;
  }

  int? get _currentNavigationLegIndex {
    final tracker = _navigationTracker;
    if (tracker == null) return null;
    if (tracker.stops.isEmpty) return null;
    final index = _currentStopIndex.clamp(0, tracker.stops.length - 1);
    return tracker.stops[index].legIndex;
  }

  List<Polyline<Object>> get _selectedRoutePolylines {
    if (_flow != GoNavigationFlow.routeSelection &&
        _flow != GoNavigationFlow.routeDetails &&
        _flow != GoNavigationFlow.navigating) {
      return const <Polyline<Object>>[];
    }

    final selected = _selectedSuggestion;
    if (selected == null) return const <Polyline<Object>>[];
    final isolatedIndex = _activeLegIsolationIndex;
    final progress = _flow == GoNavigationFlow.navigating
        ? _routeProgress
        : null;

    final polylines = <Polyline<Object>>[];
    for (var i = 0; i < selected.route.legs.length; i++) {
      if (isolatedIndex != null && i != isolatedIndex) continue;
      final leg = selected.route.legs[i];
      final encoded = leg.polyline.trim();
      if (encoded.isEmpty) continue;
      final points = decodeApiRoutePolyline(encoded);
      if (points == null || points.length < 2) continue;

      if (progress == null) {
        polylines.add(_polylineForLegPoints(leg, points));
        continue;
      }

      if (i < progress.legIndex) {
        polylines.add(
          _polylineForLegPoints(leg, points, color: _passedColorForLeg(leg)),
        );
      } else if (i > progress.legIndex) {
        polylines.add(_polylineForLegPoints(leg, points));
      } else {
        final splitPoint = _interpolateRoutePoint(
          points[progress.pointIndex],
          points[progress.pointIndex + 1],
          progress.t,
        );
        final passedPoints = <LatLng>[
          ...points.sublist(0, progress.pointIndex + 1),
          splitPoint,
        ];
        final remainingPoints = <LatLng>[
          splitPoint,
          ...points.sublist(progress.pointIndex + 1),
        ];
        if (passedPoints.length >= 2) {
          polylines.add(
            _polylineForLegPoints(
              leg,
              passedPoints,
              color: _passedColorForLeg(leg),
            ),
          );
        }
        if (remainingPoints.length >= 2) {
          polylines.add(_polylineForLegPoints(leg, remainingPoints));
        }
      }
    }
    return polylines;
  }

  List<LatLng> get _selectedRideStopPoints {
    if (_flow != GoNavigationFlow.routeSelection &&
        _flow != GoNavigationFlow.routeDetails &&
        _flow != GoNavigationFlow.navigating) {
      return const <LatLng>[];
    }

    final selected = _selectedSuggestion;
    if (selected == null) return const <LatLng>[];
    final isolatedIndex = _activeLegIsolationIndex;

    final points = <LatLng>[];

    for (var i = 0; i < selected.route.legs.length; i++) {
      if (isolatedIndex != null && i != isolatedIndex) continue;
      final leg = selected.route.legs[i];
      if (leg.type != NavigateLegType.jeepney) continue;

      final encoded = leg.polyline.trim();
      if (encoded.isEmpty) continue;

      final decoded = decodeApiRoutePolyline(encoded);
      if (decoded == null || decoded.length < 2) continue;

      final boardPoint = decoded.first;
      final alightPoint = decoded.last;
      final hasDirectJeepTransferWithoutWalk =
          i > 0 && selected.route.legs[i - 1].type == NavigateLegType.jeepney;

      if (!hasDirectJeepTransferWithoutWalk) {
        _addRideStopMarkerPoint(points, boardPoint);
      }
      _addRideStopMarkerPoint(points, alightPoint);
    }

    return points;
  }

  void _addRideStopMarkerPoint(List<LatLng> points, LatLng candidate) {
    const distance = Distance();
    for (final point in points) {
      final meters = distance.as(LengthUnit.Meter, point, candidate);
      if (meters <= 12) return;
    }
    points.add(candidate);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startFocus.addListener(_handleStartFocusChange);
    _endFocus.addListener(_handleEndFocusChange);
    _loadVectorStyle();
    _initLocation();
    _subscribeToServiceStatus();
    _subscribeToHeading();
    _initConnectivity();
    unawaited(_loadStickerUrls());
  }

  @override
  void didUpdateWidget(GoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _resetToExplore();
    }
  }

  Future<void> _loadStickerUrls() async {
    try {
      final data = await loadRoutesFromApi();
      if (!mounted) return;
      setState(() => _stickerUrlsByRouteId = _buildStickerUrlMap(data.routes));
    } catch (_) {
      try {
        final data = await loadSampleMapData();
        if (!mounted) return;
        setState(
          () => _stickerUrlsByRouteId = _buildStickerUrlMap(data.routes),
        );
      } catch (_) {
        // Leave map empty; stickers simply won't appear.
      }
    }
  }

  Map<String, List<String>> _buildStickerUrlMap(List<JeepneyRoute> routes) {
    final map = <String, List<String>>{};
    for (final route in routes) {
      if (route.id.isEmpty || route.imageUrls.isEmpty) continue;
      map[route.id] = List<String>.from(route.imageUrls);
    }
    return map;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _positionSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _headingSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _trackerSubscription?.cancel();
    _simulatorStateSubscription?.cancel();
    _navigationTracker?.stop();
    unawaited(_locationService.detachTripSimulator());
    unawaited(_tripSimulator?.dispose() ?? Future<void>.value());
    if (_bottomNavHidden) {
      widget.onBottomNavVisibilityChanged?.call(true);
    }
    _startFocus.removeListener(_handleStartFocusChange);
    _endFocus.removeListener(_handleEndFocusChange);
    _startController.dispose();
    _endController.dispose();
    _startFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  void _handleStartFocusChange() {
    _selectAllOnFocus(_startController, _startFocus);
  }

  void _handleEndFocusChange() {
    _selectAllOnFocus(_endController, _endFocus);
  }

  void _selectAllOnFocus(
    TextEditingController controller,
    FocusNode focusNode,
  ) {
    if (!focusNode.hasFocus) return;
    final text = controller.text;
    if (text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!focusNode.hasFocus) return;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadVectorStyle();
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

  void _subscribeToHeading() {
    _headingSubscription = _locationService.headingStream.listen((heading) {
      if (!mounted) return;
      setState(() => _compassHeading = heading);
    });
  }

  Future<void> _initConnectivity() async {
    final first = await _connectivity.checkConnectivity();
    if (!mounted) return;
    setState(() => _online = _hasNetworkInterface(first));
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (!mounted) return;
      setState(() => _online = _hasNetworkInterface(results));
    });
  }

  Future<void> _loadVectorStyle() async {
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
    if (!mounted) return;
    _vectorStyleAttempted = true;
    _checkReadiness();
  }

  void _markMapReady() {
    if (_mapFirstFrame) return;
    _mapFirstFrame = true;
    _checkReadiness();
  }

  void _markLocationAttempted() {
    if (_locationAttempted) return;
    _locationAttempted = true;
    _checkReadiness();
  }

  void _checkReadiness() {
    if (_readinessSignaled) return;
    if (!_vectorStyleAttempted || !_mapFirstFrame || !_locationAttempted) {
      return;
    }
    _readinessSignaled = true;
    widget.onReady?.call();
  }

  Future<void> _initLocation() async {
    final cachedPosition = _locationService.lastKnown;
    if (cachedPosition != null && mounted && _userPosition == null) {
      setState(() => _userPosition = cachedPosition);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerToUserOnce(cachedPosition);
      });
    }

    final serviceEnabled = await _locationService.isServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      setState(() {
        _permissionChecked = true;
        _locationPermission = null;
      });
      _markLocationAttempted();
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
      _markLocationAttempted();
      return;
    }

    if (_positionSubscription != null) {
      // Already subscribed; this is a re-entry after resume or service toggle.
      await _locationService.refresh();
      _markLocationAttempted();
      return;
    }

    final stream = _locationService.stream;
    _positionSubscription = stream.listen(
      (Position position) {
        if (!mounted) return;
        final shouldPrimeRoutingStart =
            _showRoutingHeader &&
            _start == null &&
            _startController.text.trim().isEmpty;

        setState(() {
          _userPosition = position;
          if (_flow == GoNavigationFlow.navigating) {
            _updateRouteProgress(position);
          }
        });

        if (shouldPrimeRoutingStart) {
          _useCurrentLocationForStart();
        }

        _centerToUserOnce(position);
        _maybeFollowUser(position);
      },
      onError: (_) {
        if (mounted) setState(() => _userPosition = null);
      },
    );
    _markLocationAttempted();
  }

  void _centerToUserOnce(Position position) {
    if (!mounted || _hasCenteredToUserOnce) return;
    if (_selectedExplorePoint != null || _end != null) return;
    _hasCenteredToUserOnce = true;
    _suppressNextGestureFollowBreak = true;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      _initialZoom,
    );
  }

  /// Fixed offset that keeps the user marker centered between the top of the
  /// screen and the top of the navigating sheet at its default height.
  Offset _followOffsetForNavigation() {
    final mapHeight = _mapController.camera.nonRotatedSize.height;
    if (mapHeight <= 0) return Offset.zero;
    final defaultSheetHeight = mapHeight * _sheetCollapsedSize;
    return Offset(0, -defaultSheetHeight / 2);
  }

  void _moveMapToFollowUser(Position position) {
    _suppressNextGestureFollowBreak = true;
    final latLng = LatLng(position.latitude, position.longitude);
    if (_flow == GoNavigationFlow.navigating) {
      _mapController.move(
        latLng,
        _mapController.camera.zoom,
        offset: _followOffsetForNavigation(),
      );
      return;
    }
    _mapController.move(latLng, _mapController.camera.zoom);
  }

  /// While in [_followUser] mode, re-center the camera on every new GPS fix
  /// so the blue dot stays glued to the viewport. Suppressed during routing
  /// flows where we want bounds-fit camera to remain authoritative.
  void _maybeFollowUser(Position position) {
    if (!_followUser) return;
    if (_flow != GoNavigationFlow.explore &&
        _flow != GoNavigationFlow.navigating) {
      return;
    }
    _moveMapToFollowUser(position);
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    if (_suppressNextGestureFollowBreak) {
      _suppressNextGestureFollowBreak = false;
      return;
    }
    if (!_followUser) return;
    setState(() => _followUser = false);
  }

  void _recenterOnUser() {
    final pos = _userPosition;
    if (pos == null) return;
    setState(() => _followUser = true);
    _moveMapToFollowUser(pos);
  }

  void _setActiveRoutingField(GoRoutingField field) {
    if (_activeRoutingField == field) return;
    setState(() => _activeRoutingField = field);
  }

  void _hideBottomNav() {
    if (_bottomNavHidden) return;
    _bottomNavHidden = true;
    widget.onBottomNavVisibilityChanged?.call(false);
  }

  void _showBottomNav() {
    if (!_bottomNavHidden) return;
    _bottomNavHidden = false;
    widget.onBottomNavVisibilityChanged?.call(true);
  }

  void _startRoutingSession({LatLng? endPoint, String? endLabel}) {
    setState(() {
      _flow = GoNavigationFlow.routingInput;
      _pinTarget = null;
      _activeRoutingField = GoRoutingField.end;
      _suggestions = const [];
      _searchError = null;
      _routePreviewLoading = false;
      _routePreviewSignature = null;
      _routeSuggestions = const [];
      _selectedSuggestionIndex = 0;
      _isolatedLegIndex = null;

      _start = null;
      _startController.clear();

      _end = endPoint;
      _endController.text = endPoint == null
          ? ''
          : (endLabel?.trim().isNotEmpty == true
                ? endLabel!.trim()
                : 'Selected location');
    });

    _useCurrentLocationForStart(triggerRequest: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_start == null) {
        _setActiveRoutingField(GoRoutingField.start);
        _startFocus.requestFocus();
        return;
      }
      if (_end == null) {
        _setActiveRoutingField(GoRoutingField.end);
        _endFocus.requestFocus();
      }
    });

    _requestNavigationIfComplete();
  }

  void _resetToExplore() {
    _searchDebounce?.cancel();
    _trackerSubscription?.cancel();
    _trackerSubscription = null;
    _navigationTracker?.stop();
    _navigationTracker = null;
    unawaited(_stopTripSimulator());

    setState(() {
      _flow = GoNavigationFlow.explore;
      _pinTarget = null;
      _activeRoutingField = GoRoutingField.end;

      _start = null;
      _end = null;
      _startController.clear();
      _endController.clear();

      _selectedExplorePoint = null;
      _selectedExploreLabel = '';

      _suggestions = const [];
      _searchError = null;
      _nominatimBusy = false;

      _routePreviewLoading = false;
      _routePreviewSignature = null;
      _routeSuggestions = const [];
      _selectedSuggestionIndex = 0;
      _isolatedLegIndex = null;
      _currentStopIndex = 0;
      _lastProximityAlertAt = null;
      _navigationBusy = false;
      _routeProgress = null;
      _followUser = true;
    });

    _startFocus.unfocus();
    _endFocus.unfocus();
    _showBottomNav();
    _resetMapToDefaultView();
  }

  void _resetMapToDefaultView() {
    final pos = _userPosition;
    if (pos != null && _gpsOriginAvailable) {
      _suppressNextGestureFollowBreak = true;
      _mapController.move(LatLng(pos.latitude, pos.longitude), _initialZoom);
      return;
    }

    _suppressNextGestureFollowBreak = true;
    _mapController.move(_iloiloCenter, _initialZoom);
  }

  void _onCollapsedTap() {
    _startRoutingSession();
  }

  void _onDirectionsFromLocationDetail() {
    final selectedPoint = _selectedExplorePoint;
    if (selectedPoint == null) return;

    _startRoutingSession(
      endPoint: selectedPoint,
      endLabel: _selectedExploreLabel,
    );
  }

  void _openStartPinOnMap() {
    setState(() {
      _pinTarget = GoPinTarget.origin;
      _activeRoutingField = GoRoutingField.start;
    });
  }

  void _openEndPinOnMap() {
    setState(() {
      _pinTarget = GoPinTarget.destination;
      _activeRoutingField = GoRoutingField.end;
    });
  }

  void _openActiveFieldPinOnMap() {
    if (_activeRoutingField == GoRoutingField.start) {
      _openStartPinOnMap();
      return;
    }
    _openEndPinOnMap();
  }

  void _cancelMapPinMode() {
    setState(() => _pinTarget = null);
  }

  LatLng _currentMapCenter() {
    return _mapController.camera.center;
  }

  Future<void> _confirmMapPinFromCenter() async {
    final target = _pinTarget;
    if (target == null) return;
    await _applyMapPinTarget(target, _currentMapCenter());
  }

  void _handleMapTap(TapPosition _, LatLng point) {
    if (_pinTarget != null) return;

    if (_flow == GoNavigationFlow.explore ||
        _flow == GoNavigationFlow.locationDetail) {
      _selectExplorePoint(point);
    }
  }

  Future<void> _selectExplorePoint(LatLng point) async {
    setState(() {
      _selectedExplorePoint = point;
      _selectedExploreLabel = 'Loading location...';
      _flow = GoNavigationFlow.locationDetail;
      _searchError = null;
      _suggestions = const [];
      _pinTarget = null;
    });

    _mapController.move(
      point,
      _mapController.camera.zoom < 15 ? 15 : _mapController.camera.zoom,
    );

    try {
      final label = await _geocoding.reverseLabel(point);
      if (!mounted) return;
      setState(() => _selectedExploreLabel = label);
    } on GeocodingException {
      if (!mounted) return;
      setState(() => _selectedExploreLabel = 'Pinned location');
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectedExploreLabel = 'Pinned location');
    }
  }

  Future<void> _applyMapPinTarget(GoPinTarget target, LatLng point) async {
    setState(() {
      _pinTarget = null;
      _searchError = null;
    });

    String label = 'Pinned location';
    try {
      label = await _geocoding.reverseLabel(point);
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      if (target == GoPinTarget.origin) {
        _start = point;
        _startController.text = label;
        _activeRoutingField = GoRoutingField.end;
      } else {
        _end = point;
        _endController.text = label;
      }
      _routePreviewSignature = null;
      _suggestions = const [];
    });

    _dismissKeyboard();

    _requestNavigationIfComplete();
  }

  void _useCurrentLocationForStart({bool triggerRequest = true}) {
    final pos = _userPosition;
    if (pos == null || !_gpsOriginAvailable) return;
    setState(() {
      _pinTarget = null;
      _start = LatLng(pos.latitude, pos.longitude);
      _startController.text = 'Your location';
      _routePreviewSignature = null;
      if (_activeRoutingField == GoRoutingField.start) {
        _activeRoutingField = GoRoutingField.end;
      }
    });

    _dismissKeyboard();

    if (triggerRequest) {
      _requestNavigationIfComplete();
    }
  }

  void _onStartTextChanged(String raw) {
    _setActiveRoutingField(GoRoutingField.start);
    setState(() {
      _start = null;
      _routePreviewSignature = null;
    });
    _onSearchQueryChanged(raw);
  }

  void _onEndTextChanged(String raw) {
    _setActiveRoutingField(GoRoutingField.end);
    setState(() {
      _end = null;
      _routePreviewSignature = null;
    });
    _onSearchQueryChanged(raw);
  }

  void _onEndSearchSubmitted(String raw) {
    _setActiveRoutingField(GoRoutingField.end);
    _dismissKeyboard();
    final q = raw.trim();
    if (q.isEmpty) {
      _onSearchQueryChanged(raw);
      return;
    }

    _searchDebounce?.cancel();
    _runForwardSearch(q);
  }

  void _onSearchQueryChanged(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestions = const [];
        _searchError = null;
        _nominatimBusy = false;
      });
      _requestNavigationIfComplete();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _runForwardSearch(q);
    });
  }

  Future<void> _runForwardSearch(String q) async {
    setState(() {
      _nominatimBusy = true;
      _searchError = null;
    });
    try {
      final hits = await _geocoding.searchPlaces(q);
      if (!mounted) return;
      setState(() {
        _suggestions = hits;
        _nominatimBusy = false;
      });
    } on GeocodingException {
      if (!mounted) return;
      setState(() {
        _suggestions = const [];
        _nominatimBusy = false;
        _searchError =
            'Connection problem - please check your internet and try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = const [];
        _nominatimBusy = false;
        _searchError =
            'Connection problem - please check your internet and try again.';
      });
    }
  }

  void _onPickSuggestion(NominatimSearchHit hit) {
    setState(() {
      if (_activeRoutingField == GoRoutingField.start) {
        _start = hit.point;
        _startController.text = hit.displayName;
      } else {
        _end = hit.point;
        _endController.text = hit.displayName;
      }
      _suggestions = const [];
      _searchError = null;
      _routePreviewSignature = null;
    });

    _dismissKeyboard();

    if (_activeRoutingField == GoRoutingField.start && _end == null) {
      _setActiveRoutingField(GoRoutingField.end);
      _endFocus.requestFocus();
    }

    _requestNavigationIfComplete();
  }

  void _dismissKeyboard() {
    _startFocus.unfocus();
    _endFocus.unfocus();
  }

  Future<void> _requestNavigationIfComplete() async {
    final start = _start;
    final end = _end;
    if (start == null || end == null) {
      if (_showRoutingHeader) {
        setState(() {
          _routePreviewSignature = null;
          _routePreviewLoading = false;
          _routeSuggestions = const [];
          _selectedSuggestionIndex = 0;
          _isolatedLegIndex = null;
          _flow = GoNavigationFlow.routingInput;
        });
      }
      return;
    }

    final sig =
        '${start.latitude.toStringAsFixed(5)},${start.longitude.toStringAsFixed(5)}|'
        '${end.latitude.toStringAsFixed(5)},${end.longitude.toStringAsFixed(5)}';
    if (_routePreviewSignature == sig && _routeSuggestions.isNotEmpty) {
      return;
    }

    _routePreviewSignature = sig;
    final requestToken = ++_navigateRequestToken;

    setState(() {
      _routePreviewLoading = true;
      _searchError = null;
      _flow = GoNavigationFlow.routeSelection;
      _routeSuggestions = const [];
      _selectedSuggestionIndex = 0;
      _isolatedLegIndex = null;
    });
    _hideBottomNav();

    _collapseRouteSelectionSheetForLoading();

    try {
      final suggestions = await fetchNavigationSuggestions(
        start: start,
        end: end,
      );
      if (!mounted || requestToken != _navigateRequestToken) return;

      if (suggestions.isEmpty) {
        setState(() {
          _routePreviewLoading = false;
          _flow = GoNavigationFlow.routeSelection;
          _searchError = 'No route suggestions found for this trip.';
        });
        return;
      }

      final prioritized = _prioritizeSuggestions(suggestions);
      setState(() {
        _routePreviewLoading = false;
        _routeSuggestions = prioritized;
        _selectedSuggestionIndex = 0;
        _isolatedLegIndex = null;
        _flow = GoNavigationFlow.routeSelection;
      });

      _fitRouteOrStartEnd();
      _snapRouteSelectionSheetToDefault();
    } on NavigateRequestException catch (e) {
      if (!mounted || requestToken != _navigateRequestToken) return;
      setState(() {
        _routePreviewLoading = false;
        _flow = GoNavigationFlow.routeSelection;
        _searchError = e.message;
      });
    } catch (_) {
      if (!mounted || requestToken != _navigateRequestToken) return;
      setState(() {
        _routePreviewLoading = false;
        _flow = GoNavigationFlow.routeSelection;
        _searchError =
            'Connection problem - please check your internet and try again.';
      });
    }
  }

  List<NavigateSuggestion> _prioritizeSuggestions(
    List<NavigateSuggestion> suggestions,
  ) {
    if (suggestions.isEmpty) return const [];

    final grouped = <NavigateSuggestionLabel, List<NavigateSuggestion>>{};
    for (final suggestion in suggestions) {
      grouped.putIfAbsent(suggestion.label, () => []).add(suggestion);
    }

    final priority = <NavigateSuggestionLabel>[
      NavigateSuggestionLabel.simplest,
      NavigateSuggestionLabel.fastest,
      NavigateSuggestionLabel.leastWalking,
      NavigateSuggestionLabel.explorer,
      NavigateSuggestionLabel.unknown,
    ];

    final selected = <NavigateSuggestion>[];
    for (final label in priority) {
      final group = grouped[label];
      if (group == null || group.isEmpty) continue;
      selected.add(group.first);
      if (selected.length == 3) return selected;
    }

    for (final label in priority) {
      final group = grouped[label];
      if (group == null || group.isEmpty) continue;
      for (final suggestion in group) {
        if (selected.length == 3) return selected;
        if (selected.contains(suggestion)) continue;
        selected.add(suggestion);
      }
    }

    return selected;
  }

  void _onSuggestionCardSelected(int index) {
    if (index < 0 || index >= _routeSuggestions.length) return;
    if (_selectedSuggestionIndex == index) return;
    setState(() {
      _selectedSuggestionIndex = index;
      _isolatedLegIndex = null;
    });
    _fitRouteOrStartEnd();
  }

  Future<void> _startNavigating() async {
    final selected = _selectedSuggestion;
    if (selected == null || _navigationBusy) return;

    setState(() => _navigationBusy = true);
    try {
      final permission = await _locationService.requestPermission();
      if (!mounted) return;
      setState(() {
        _permissionChecked = true;
        _locationPermission = permission;
      });
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showTopSnackBar(
          'Location permission is required to start trip notifications.',
        );
        return;
      }

      final locationAlways = await Permission.locationAlways.request();
      if (!mounted) return;
      if (!locationAlways.isGranted) {
        _showTopSnackBar(
          'Background alerts are limited until "Allow all the time" is granted.',
        );
      }

      await NotificationService.instance.requestPermissions();

      await _trackerSubscription?.cancel();
      _trackerSubscription = null;
      await _navigationTracker?.stop();
      _navigationTracker = null;

      final tracker = NavigationTracker(
        suggestion: selected,
        thresholdMeters: 100,
      );
      _trackerSubscription = tracker.events.listen((event) {
        _onProximityEvent(event);
      });
      tracker.start();

      if (kDebugMode && _debugTripSimulatorEnabled) {
        await _startTripSimulator(selected);
      } else {
        await _stopTripSimulator();
      }

      if (!mounted) return;
      setState(() {
        _navigationTracker = tracker;
        _currentStopIndex = 0;
        _flow = GoNavigationFlow.navigating;
        _isolatedLegIndex = null;
        _lastProximityAlertAt = null;
        _routeProgress = null;
        _followUser = true;
        final position = _userPosition;
        if (position != null) {
          _updateRouteProgress(position);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _flow != GoNavigationFlow.navigating) return;
        final position = _userPosition;
        if (position != null) {
          _moveMapToFollowUser(position);
        }
      });
    } finally {
      if (mounted) {
        setState(() => _navigationBusy = false);
      }
    }
  }

  Future<void> _startTripSimulator(NavigateSuggestion suggestion) async {
    if (!kDebugMode || !_debugTripSimulatorEnabled) return;

    await _stopTripSimulator();
    final simulator = TripSimulatorService.fromSuggestion(
      suggestion: suggestion,
    );
    if (simulator.totalPoints < 2) {
      await simulator.dispose();
      if (mounted) {
        _showTopSnackBar('Trip simulator unavailable for this route.');
      }
      return;
    }

    _simulatorStateSubscription = simulator.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _tripSimulatorState = state);
    });
    await _locationService.attachTripSimulator(simulator);
    _tripSimulator = simulator;
    if (mounted) {
      setState(() => _tripSimulatorState = simulator.snapshot);
    }
  }

  Future<void> _stopTripSimulator() async {
    await _locationService.detachTripSimulator();
    await _simulatorStateSubscription?.cancel();
    _simulatorStateSubscription = null;
    await _tripSimulator?.dispose();
    _tripSimulator = null;
    if (!mounted) return;
    setState(() => _tripSimulatorState = TripSimulatorState.idle);
  }

  void _onDebugSimulatorToggled(bool enabled) {
    if (!kDebugMode) return;
    setState(() {
      _debugTripSimulatorEnabled = enabled;
      if (!enabled) {
        _tripSimulatorState = TripSimulatorState.idle;
      }
    });
    if (!enabled) {
      unawaited(_stopTripSimulator());
      return;
    }
    final selected = _selectedSuggestion;
    if (selected == null) return;
    if (_flow == GoNavigationFlow.navigating) {
      unawaited(_startTripSimulator(selected));
    }
  }

  void _jumpSimulatorToNextStop() {
    final simulator = _tripSimulator;
    final tracker = _navigationTracker;
    if (simulator == null || tracker == null || tracker.stops.isEmpty) return;
    final stopIndex = _currentStopIndex.clamp(0, tracker.stops.length - 1);
    simulator.jumpNearStop(tracker.stops[stopIndex]);
    setState(() => _tripSimulatorState = simulator.snapshot);
  }

  void _moveSimulatorOverlay(Offset delta) {
    setState(() {
      _simOverlayOffset = Offset(
        _simOverlayOffset.dx + delta.dx,
        (_simOverlayOffset.dy + delta.dy).clamp(72.0, 520.0),
      );
    });
  }

  void _toggleSimulatorPlayback() {
    final simulator = _tripSimulator;
    if (simulator == null) return;
    if (_tripSimulatorState.isPlaying) {
      simulator.pause();
    } else {
      simulator.play();
    }
    setState(() => _tripSimulatorState = simulator.snapshot);
  }

  void _stepTripSimulator() {
    final simulator = _tripSimulator;
    if (simulator == null) return;
    simulator.stepForward();
    setState(() => _tripSimulatorState = simulator.snapshot);
  }

  void _stopTripSimulatorPlayback() {
    final simulator = _tripSimulator;
    if (simulator == null) return;
    simulator.stop();
    setState(() => _tripSimulatorState = simulator.snapshot);
  }

  void _setTripSimulatorSpeed(double speed) {
    final simulator = _tripSimulator;
    if (simulator == null) return;
    simulator.setSpeedMultiplier(speed);
    setState(() => _tripSimulatorState = simulator.snapshot);
  }

  Future<void> _onProximityEvent(ProximityEvent event) async {
    if (!mounted) return;

    final title = event.stop.kind == TripStopKind.dropOff
        ? 'Arriving at your destination'
        : 'Transfer ahead - get ready to alight';
    final body =
        '${event.distanceMeters.round()}m to ${event.stop.label.trim().isEmpty ? 'next stop' : event.stop.label}';

    var shouldNotify = true;
    if (kDebugMode && _debugTripSimulatorEnabled) {
      final now = DateTime.now();
      final last = _lastProximityAlertAt;
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        shouldNotify = false;
      } else {
        _lastProximityAlertAt = now;
      }
    }

    if (shouldNotify) {
      _showTopSnackBar(body, title: title);
      await NotificationService.instance.showProximityNotification(
        title: title,
        body: body,
      );

      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        await Vibration.vibrate(pattern: const [0, 400, 200, 400]);
      }
    }

    if (!mounted) return;
    setState(() {
      _currentStopIndex =
          _navigationTracker?.currentStopIndex ?? _currentStopIndex;
    });

    if (event.tripComplete) {
      await _endNavigating(showCompletedMessage: true);
    }
  }

  Future<void> _endNavigating({bool showCompletedMessage = false}) async {
    if (_navigationBusy) return;

    setState(() => _navigationBusy = true);
    try {
      await _stopTripSimulator();
      await _trackerSubscription?.cancel();
      _trackerSubscription = null;
      await _navigationTracker?.stop();
      _navigationTracker = null;
      if (!mounted) return;
      setState(() {
        _currentStopIndex = 0;
        _flow = GoNavigationFlow.routeDetails;
        _isolatedLegIndex = null;
        _lastProximityAlertAt = null;
        _routeProgress = null;
      });
      _showBottomNav();
      if (showCompletedMessage) {
        _showTopSnackBar('You are at your destination. Trip finished.');
      }
    } finally {
      if (mounted) {
        setState(() => _navigationBusy = false);
      }
    }
  }

  void _showTopSnackBar(String message, {String? title}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MapColors.text,
        content: Text(
          title == null ? message : '$title\n$message',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: MapColors.secondary,
          onPressed: () {},
        ),
      ),
    );
  }

  void _onLegTimelineStepTapped(int legIndex) {
    final selected = _selectedSuggestion;
    if (selected == null) return;
    if (legIndex < 0 || legIndex >= selected.route.legs.length) return;

    final nextIsolation = _isolatedLegIndex == legIndex ? null : legIndex;
    setState(() => _isolatedLegIndex = nextIsolation);

    if (nextIsolation == null) {
      _fitRouteOrStartEnd();
      _expandRouteDetailsSheetToDefault();
      return;
    }

    _collapseRouteDetailsSheetForFocus();

    final encoded = selected.route.legs[nextIsolation].polyline.trim();
    if (encoded.isEmpty) return;

    final points = decodeApiRoutePolyline(encoded);
    if (points == null || points.isEmpty) return;

    if (points.length == 1) {
      _mapController.move(points.first, 16);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(56, 168, 56, 136),
        ),
      );
    } catch (_) {
      _mapController.move(bounds.center, _mapController.camera.zoom);
    }
  }

  void _showAllRouteSteps() {
    if (_isolatedLegIndex == null) return;
    setState(() => _isolatedLegIndex = null);
    _fitRouteOrStartEnd();
    _expandRouteDetailsSheetToDefault();
  }

  void _collapseRouteDetailsSheetForFocus() {
    if (_flow != GoNavigationFlow.routeDetails) return;
    try {
      _sheetController.animateTo(
        _sheetCollapsedSize,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  void _collapseRouteSelectionSheetForLoading() {
    if (_flow != GoNavigationFlow.routeSelection) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_flow != GoNavigationFlow.routeSelection || !_routePreviewLoading) {
        return;
      }

      try {
        _sheetController.animateTo(
          _sheetCollapsedSize,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    });
  }

  void _snapRouteSelectionSheetToDefault() {
    if (_flow != GoNavigationFlow.routeSelection) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_flow != GoNavigationFlow.routeSelection) return;

      try {
        await _sheetController.animateTo(
          _sheetDefaultSize,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        if (mounted) setState(() {});
      } catch (_) {}
    });
  }

  void _expandRouteDetailsSheetToDefault() {
    if (_flow != GoNavigationFlow.routeDetails) return;
    try {
      _sheetController.animateTo(
        _sheetDefaultSize,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  int _rideCountForSuggestion(NavigateSuggestion suggestion) {
    return suggestion.route.legs
        .where((leg) => leg.type == NavigateLegType.jeepney)
        .length;
  }

  String _modeSummaryForSuggestion(NavigateSuggestion suggestion) {
    final labels = <String>[];
    for (final leg in suggestion.route.legs) {
      final label = switch (leg.type) {
        NavigateLegType.walk => 'Walk',
        NavigateLegType.jeepney => 'Jeep',
        NavigateLegType.tricycle => 'Tricycle',
        NavigateLegType.unknown => 'Transit',
      };
      if (labels.isEmpty || labels.last != label) {
        labels.add(label);
      }
    }
    if (labels.isEmpty) return 'Transit';
    return labels.join(' + ');
  }

  Color _accentColorForSuggestion(NavigateSuggestion suggestion, int index) {
    for (final leg in suggestion.route.legs) {
      if (leg.type != NavigateLegType.walk) {
        return _colorForLeg(leg);
      }
    }

    if (suggestion.route.legs.isNotEmpty) {
      return _colorForLeg(suggestion.route.legs.first);
    }

    return switch (index % 3) {
      0 => MapColors.primary,
      1 => MapColors.secondary,
      _ => MapColors.accent,
    };
  }

  String _routeBadgeText(NavigateSuggestion suggestion, int index) {
    if (_isBestSuggestionIndex(index)) return 'Best';
    return suggestion.labelText;
  }

  bool _isBestSuggestionIndex(int index) => index == 0;

  Color _badgeTextColor(Color background) {
    return background.computeLuminance() > 0.55 ? MapColors.text : Colors.white;
  }

  void _fitRouteOrStartEnd() {
    if (_followUser) {
      _followUser = false;
    }
    final selected = _selectedSuggestion;
    final points = <LatLng>[];

    if (selected != null) {
      for (final leg in selected.route.legs) {
        final encoded = leg.polyline.trim();
        if (encoded.isEmpty) continue;
        final decoded = decodeApiRoutePolyline(encoded);
        if (decoded == null || decoded.length < 2) continue;
        points.addAll(decoded);
      }
    }

    if (points.length < 2) {
      final s = _start;
      final e = _end;
      if (s != null) points.add(s);
      if (e != null) points.add(e);
    }

    if (points.isEmpty) return;

    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(48, 160, 48, 120),
        ),
      );
    } catch (_) {
      _mapController.move(bounds.center, _mapController.camera.zoom);
    }
  }

  Color _colorForLeg(NavigateLeg leg) {
    final fromApi = leg.colorHex;
    if (fromApi != null && fromApi.isNotEmpty) {
      return parseRouteColor(fromApi);
    }

    return switch (leg.type) {
      NavigateLegType.walk => MapColors.walkingColor,
      NavigateLegType.jeepney => MapColors.jeepneyRouteColor,
      NavigateLegType.tricycle => MapColors.accentColor,
      NavigateLegType.unknown => MapColors.primary,
    };
  }

  Color _mapColorForLeg(NavigateLeg leg) {
    if (leg.type == NavigateLegType.walk) {
      return const Color(0xFF9E9E9E);
    }
    return _colorForLeg(leg);
  }

  StrokePattern _polylinePatternForLeg(NavigateLeg leg) {
    if (leg.type == NavigateLegType.walk) {
      return StrokePattern.dashed(segments: const <double>[7, 5]);
    }
    return const StrokePattern.solid();
  }

  double _strokeWidthForLeg(NavigateLeg leg) {
    return switch (leg.type) {
      NavigateLegType.walk => MapColors.walkingStrokeWidth,
      NavigateLegType.jeepney => MapColors.jeepneyRouteStrokeWidth,
      NavigateLegType.tricycle => MapColors.accentStrokeWidth,
      NavigateLegType.unknown => MapColors.jeepneyRouteStrokeWidth,
    };
  }

  Polyline<Object> _polylineForLegPoints(
    NavigateLeg leg,
    List<LatLng> points, {
    Color? color,
  }) {
    return Polyline<Object>(
      points: points,
      color: color ?? _mapColorForLeg(leg),
      strokeWidth: _strokeWidthForLeg(leg),
      pattern: _polylinePatternForLeg(leg),
    );
  }

  Color _passedColorForLeg(NavigateLeg leg) {
    return _mapColorForLeg(leg).withValues(alpha: 0.35);
  }

  LatLng _interpolateRoutePoint(LatLng start, LatLng end, double t) {
    final clamped = t.clamp(0.0, 1.0);
    return LatLng(
      start.latitude + (end.latitude - start.latitude) * clamped,
      start.longitude + (end.longitude - start.longitude) * clamped,
    );
  }

  int _compareRouteProgress(RouteProgress a, RouteProgress b) {
    if (a.legIndex != b.legIndex) {
      return a.legIndex.compareTo(b.legIndex);
    }
    if (a.pointIndex != b.pointIndex) {
      return a.pointIndex.compareTo(b.pointIndex);
    }
    return a.t.compareTo(b.t);
  }

  bool _isRouteProgressAhead(RouteProgress candidate, RouteProgress current) {
    return _compareRouteProgress(candidate, current) > 0;
  }

  ({double t, double distanceMeters}) _projectOntoRouteSegment(
    LatLng point,
    LatLng start,
    LatLng end,
  ) {
    final latScale = 111320.0;
    final lonScale = 111320.0 * math.cos(start.latitude * math.pi / 180.0);

    final segmentX = (end.longitude - start.longitude) * lonScale;
    final segmentY = (end.latitude - start.latitude) * latScale;
    final pointX = (point.longitude - start.longitude) * lonScale;
    final pointY = (point.latitude - start.latitude) * latScale;

    final segmentLengthSquared = segmentX * segmentX + segmentY * segmentY;
    if (segmentLengthSquared == 0) {
      final distance = const Distance().as(LengthUnit.Meter, start, point);
      return (t: 0.0, distanceMeters: distance);
    }

    final t = ((pointX * segmentX + pointY * segmentY) / segmentLengthSquared)
        .clamp(0.0, 1.0);
    final projected = _interpolateRoutePoint(start, end, t);
    final distance = const Distance().as(LengthUnit.Meter, point, projected);
    return (t: t, distanceMeters: distance);
  }

  void _updateRouteProgress(Position position) {
    final selected = _selectedSuggestion;
    if (selected == null) return;

    final userPoint = LatLng(position.latitude, position.longitude);
    final legs = selected.route.legs;
    if (legs.isEmpty) return;

    final startLegIndex = _routeProgress?.legIndex ?? 0;
    RouteProgress? bestCandidate;
    var bestDistance = double.infinity;

    for (var legIndex = startLegIndex; legIndex < legs.length; legIndex++) {
      final encoded = legs[legIndex].polyline.trim();
      if (encoded.isEmpty) continue;
      final points = decodeApiRoutePolyline(encoded);
      if (points == null || points.length < 2) continue;

      final startPointIndex = legIndex == startLegIndex
          ? (_routeProgress?.pointIndex ?? 0)
          : 0;

      for (
        var pointIndex = startPointIndex;
        pointIndex < points.length - 1;
        pointIndex++
      ) {
        final projection = _projectOntoRouteSegment(
          userPoint,
          points[pointIndex],
          points[pointIndex + 1],
        );
        if (projection.distanceMeters >= bestDistance) continue;

        bestDistance = projection.distanceMeters;
        bestCandidate = (
          legIndex: legIndex,
          pointIndex: pointIndex,
          t: projection.t,
        );
      }
    }

    if (bestCandidate == null || bestDistance > _routeProgressSnapMaxMeters) {
      return;
    }

    final current = _routeProgress;
    if (current != null && !_isRouteProgressAhead(bestCandidate, current)) {
      return;
    }

    _routeProgress = bestCandidate;
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  String _formatMinutes(double minutes) {
    if (minutes.isNaN || minutes.isInfinite || minutes <= 0) return '0 min';

    final totalSeconds = (minutes * 60).round();
    if (totalSeconds < 60) return '$totalSeconds sec';

    final roundedMinutes = (totalSeconds / 60).round();
    if (roundedMinutes < 60) return '$roundedMinutes min';

    final hours = roundedMinutes ~/ 60;
    final mins = roundedMinutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  int _previewInstructionCount(NavigateSuggestion suggestion) {
    var count = 0;
    for (final leg in suggestion.route.legs) {
      if (_previewInstructionText(leg).isEmpty) continue;
      count += 1;
      if (count >= 5) break;
    }
    return count;
  }

  IconData _iconForLegType(NavigateLegType type) {
    return switch (type) {
      NavigateLegType.walk => Icons.directions_walk_rounded,
      NavigateLegType.jeepney => Icons.directions_bus_rounded,
      NavigateLegType.tricycle => Icons.pedal_bike_rounded,
      NavigateLegType.unknown => Icons.route_rounded,
    };
  }

  IconData _iconForManeuver(NavigateManeuverType maneuver) {
    return switch (maneuver) {
      NavigateManeuverType.board => Icons.login_rounded,
      NavigateManeuverType.alight => Icons.logout_rounded,
      NavigateManeuverType.depart => Icons.near_me_rounded,
      NavigateManeuverType.turn => Icons.turn_right_rounded,
      NavigateManeuverType.arrive => Icons.flag_rounded,
      NavigateManeuverType.unknown => Icons.chevron_right_rounded,
    };
  }

  IconData _iconForInstruction({
    required NavigateLeg leg,
    required NavigateInstruction instruction,
    required bool isTransferBoard,
  }) {
    if (instruction.maneuverType == NavigateManeuverType.alight) {
      return Icons.location_on;
    }

    if (instruction.maneuverType == NavigateManeuverType.board) {
      if (isTransferBoard) return Icons.swap_horiz;
      if (leg.type == NavigateLegType.jeepney) return Icons.directions_bus;
      return _iconForManeuver(instruction.maneuverType);
    }

    if (leg.type == NavigateLegType.walk) {
      return Icons.directions_walk;
    }
    if (leg.type == NavigateLegType.jeepney) {
      return Icons.directions_bus;
    }

    return _iconForManeuver(instruction.maneuverType);
  }

  Color _colorForManeuver(NavigateManeuverType maneuver) {
    return switch (maneuver) {
      NavigateManeuverType.board => MapColors.primary,
      NavigateManeuverType.alight => MapColors.accent,
      NavigateManeuverType.depart => MapColors.secondary,
      NavigateManeuverType.turn => MapColors.text,
      NavigateManeuverType.arrive => MapColors.accent,
      NavigateManeuverType.unknown => MapColors.text.withValues(alpha: 0.7),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_online) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 56,
                  color: MapColors.text.withValues(alpha: 0.45),
                ),
                const SizedBox(height: 20),
                Text(
                  'Go is not available offline.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  'Switch to the Routes tab to browse routes while you are offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MapColors.text.withValues(alpha: 0.72),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final userLatLng = _userPosition == null
        ? null
        : LatLng(_userPosition!.latitude, _userPosition!.longitude);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GoMapCanvas(
              mapController: _mapController,
              vectorStyle: _vectorStyle,
              initialCenter: _iloiloCenter,
              initialZoom: _initialZoom,
              onMapTap: _handleMapTap,
              routePolylines: _selectedRoutePolylines,
              dropOffPoints: _selectedRideStopPoints,
              userPosition: userLatLng,
              userHeading: _compassHeading,
              userSpeedMps: _userPosition?.speed,
              userAccuracyMeters: _userPosition?.accuracy,
              origin: _mapOrigin,
              destination: _mapDestination,
              osmTileUrl: _osmTileUrl,
              userAgentPackageName: _userAgentPackageName,
              onPositionChanged: _onMapPositionChanged,
              onMapReady: _markMapReady,
            ),
          ),
          if (_pinTarget != null) _buildCenterPinCrosshair(),
          GoRecenterButton(
            userPosition: _userPosition,
            mapController: _mapController,
            isFollowing: _followUser,
            onRecenter: _recenterOnUser,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GoSearchBar(
                    mode: _searchMode,
                    onCollapsedTap: _onCollapsedTap,
                    startController: _startController,
                    startFocusNode: _startFocus,
                    endController: _endController,
                    endFocusNode: _endFocus,
                    onStartTextChanged: _onStartTextChanged,
                    onEndTextChanged: _onEndTextChanged,
                    onEndSubmitted: _onEndSearchSubmitted,
                    showUseCurrentLocation: _gpsOriginAvailable,
                    onUseCurrentLocationTap: _useCurrentLocationForStart,
                    suggestions: _suggestions,
                    onSuggestionTap: _onPickSuggestion,
                    searchError: _flow == GoNavigationFlow.routeSelection
                        ? null
                        : _searchError,
                    showOutOfAreaDisclaimer: _destinationOutOfArea,
                    isSearchingNominatim: _nominatimBusy,
                    activeRoutingField: _activeRoutingField,
                    onActiveRoutingFieldChanged: _setActiveRoutingField,
                  ),
                  if (_searchMode == GoSearchBarMode.expanded &&
                      _flow != GoNavigationFlow.navigating &&
                      _pinTarget == null) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: GoManualPinLocationButton(
                        onTap: _openActiveFieldPinOnMap,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_flow != GoNavigationFlow.navigating && _pinTarget != null)
            _buildPinModeSheet()
          else if (_flow == GoNavigationFlow.locationDetail)
            _buildLocationDetailSheet(),
          if (_flow == GoNavigationFlow.navigating) _buildNavigatingSheet(),
          if (_flow != GoNavigationFlow.navigating &&
              _pinTarget == null &&
              _flow == GoNavigationFlow.routeSelection)
            _buildRouteSelectionSheet(),
          if (_flow != GoNavigationFlow.navigating &&
              _pinTarget == null &&
              _flow == GoNavigationFlow.routeDetails)
            _buildRouteDetailsSheet(),
          if (_permissionChecked &&
              (_locationPermission == LocationPermission.denied ||
                  _locationPermission == LocationPermission.deniedForever ||
                  _locationPermission == null))
            MapLocationMessage(
              message: _locationPermission == null
                  ? 'Location service is disabled.'
                  : 'Location permission denied. Enable it to see your position on the Go map.',
            ),
          if (kDebugMode &&
              _flow == GoNavigationFlow.navigating &&
              _debugTripSimulatorEnabled)
            Positioned(
              top: _simOverlayOffset.dy,
              right: 12 - _simOverlayOffset.dx,
              child: DebugTripSimulatorOverlay(
                state: _tripSimulatorState,
                simulatorAvailable: _tripSimulator != null,
                onPlayPause: _toggleSimulatorPlayback,
                onStep: _stepTripSimulator,
                onJumpToNextStop: _jumpSimulatorToNextStop,
                onStop: _stopTripSimulatorPlayback,
                onSpeedChanged: _setTripSimulatorSpeed,
                onDragDelta: _moveSimulatorOverlay,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterPinCrosshair() {
    const pinSize = 34.0;
    // place_rounded tip sits slightly above the bottom of the icon box; lift so
    // the sharp point (not the box bottom) matches the map center.
    const tipInsetFromBoxBottom = 3.0;
    const lift = pinSize / 2 - tipInsetFromBoxBottom;
    final pinColor = _pinTarget == GoPinTarget.destination
        ? MapColors.secondary
        : MapColors.primary;
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -lift),
          child: Icon(
            Icons.place_rounded,
            color: pinColor,
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
      ),
    );
  }

  Widget _buildPinModeSheet() {
    final isOrigin = _pinTarget == GoPinTarget.origin;
    final title = isOrigin ? 'Pin starting point' : 'Pin destination';
    final body = isOrigin
        ? 'Move the map so the crosshair points to your starting location.'
        : 'Move the map so the crosshair points to your destination.';

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _sheetCollapsedSize,
      minChildSize: _sheetCollapsedSize,
      maxChildSize: _sheetMaxSize,
      snap: true,
      snapSizes: _sheetSnapSizes,
      builder: (context, scrollController) {
        return _SheetSurface(
          sheetController: _sheetController,
          scrollController: scrollController,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: MapColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: TextStyle(
                  color: MapColors.text.withValues(alpha: 0.78),
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelMapPinMode,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        side: BorderSide(
                          color: MapColors.text.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirmMapPinFromCenter,
                      style: FilledButton.styleFrom(
                        backgroundColor: MapColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text(
                        'Confirm pin',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigatingSheet() {
    final tracker = _navigationTracker;
    if (tracker == null || tracker.stops.isEmpty) {
      return const SizedBox.shrink();
    }
    final clampedIndex = _currentStopIndex.clamp(0, tracker.stops.length - 1);
    final nextStop = tracker.stops[clampedIndex];
    final userPosition = _userPosition;
    final hasLiveFix = userPosition != null && _gpsOriginAvailable;

    double? distanceMeters;
    if (hasLiveFix) {
      const distance = Distance();
      distanceMeters = distance.as(
        LengthUnit.Meter,
        LatLng(userPosition.latitude, userPosition.longitude),
        nextStop.point,
      );
    }

    final nextLabel = nextStop.kind == TripStopKind.dropOff
        ? 'Destination'
        : nextStop.label;

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _sheetCollapsedSize,
      minChildSize: _sheetCollapsedSize,
      maxChildSize: _sheetMaxSize,
      snap: true,
      snapSizes: _sheetSnapSizes,
      builder: (context, scrollController) {
        return _SheetSurface(
          sheetController: _sheetController,
          scrollController: scrollController,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 20),
            children: [
              const Text(
                'Navigating',
                style: TextStyle(
                  color: MapColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Next stop: $nextLabel',
                style: TextStyle(
                  color: MapColors.text.withValues(alpha: 0.86),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                distanceMeters == null
                    ? 'Waiting for GPS...'
                    : '${distanceMeters.round()}m away',
                style: TextStyle(
                  color: MapColors.text.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              _buildStopProgressIndicator(tracker),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _navigationBusy ? null : _endNavigating,
                style: FilledButton.styleFrom(
                  backgroundColor: MapColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: _navigationBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.stop_circle_outlined),
                label: Text(
                  _navigationBusy ? 'Ending…' : 'End trip',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 18),
              Divider(color: MapColors.text.withValues(alpha: 0.12)),
              const SizedBox(height: 12),
              const Text(
                'Itinerary',
                style: TextStyle(
                  color: MapColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              ..._buildLegBlocks(withCompletedState: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStopProgressIndicator(NavigationTracker tracker) {
    final totalStops = tracker.stops.length;
    if (totalStops == 0) return const SizedBox.shrink();

    final completedStops = _currentStopIndex.clamp(0, totalStops);
    final progress = completedStops / totalStops;
    final label = completedStops >= totalStops
        ? 'Arrived'
        : 'Stop ${(completedStops + 1).clamp(1, totalStops)} of $totalStops';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _sheetSurfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MapColors.text.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: MapColors.text.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  MapColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: MapColors.text.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugSimulatorToggleTile() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MapColors.text.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.bug_report_outlined,
            size: 18,
            color: MapColors.text,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Enable Trip Simulator (debug)',
              style: TextStyle(
                color: MapColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: _debugTripSimulatorEnabled,
            onChanged: _onDebugSimulatorToggled,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationDetailSheet() {
    final selectedPoint = _selectedExplorePoint;
    if (selectedPoint == null) {
      return const SizedBox.shrink();
    }

    final title = _selectedExploreLabel.trim().isEmpty
        ? 'Selected location'
        : _selectedExploreLabel;

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _sheetCollapsedSize,
      minChildSize: _sheetCollapsedSize,
      maxChildSize: _sheetMaxSize,
      snap: true,
      snapSizes: _sheetSnapSizes,
      builder: (context, scrollController) {
        return _SheetSurface(
          sheetController: _sheetController,
          scrollController: scrollController,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MapColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: _resetToExplore,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${selectedPoint.latitude.toStringAsFixed(5)}, ${selectedPoint.longitude.toStringAsFixed(5)}',
                style: TextStyle(
                  color: MapColors.text.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MapColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _onDirectionsFromLocationDetail,
                icon: const Icon(Icons.navigation_rounded),
                label: const Text(
                  'Directions',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRouteSelectionSheet() {
    final selected = _selectedSuggestion;
    final showRouteError = _searchError != null && !_routePreviewLoading;
    const errorColor = Color(0xFFB00020);

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _sheetDefaultSize,
      minChildSize: _sheetCollapsedSize,
      maxChildSize: _sheetMaxSize,
      snap: true,
      snapSizes: _sheetSnapSizes,
      builder: (context, scrollController) {
        return _SheetSurface(
          sheetController: _sheetController,
          scrollController: scrollController,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Route Suggestions',
                          style: TextStyle(
                            color: MapColors.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _resetToExplore,
                        style: TextButton.styleFrom(
                          foregroundColor: MapColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showRouteError) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: errorColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: errorColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: errorColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _searchError!,
                                  style: const TextStyle(
                                    color: errorColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _requestNavigationIfComplete,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MapColors.primary,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_routeSuggestions.isEmpty &&
                      !_routePreviewLoading) ...[
                    const SizedBox(height: 10),
                    Text(
                      'No route suggestions available yet.',
                      style: TextStyle(
                        color: MapColors.text.withValues(alpha: 0.72),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else ...[
                    SizedBox(height: 96, child: _buildSuggestedRoutesStrip()),
                    if (_routeSuggestions.length > 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.swipe_left_rounded,
                            size: 14,
                            color: MapColors.text.withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Swipe to see more route options',
                            style: TextStyle(
                              color: MapColors.text.withValues(alpha: 0.6),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  if (selected != null) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: MapColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _navigationBusy ? null : _startNavigating,
                      icon: _navigationBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        _navigationBusy ? 'Starting…' : 'Start',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 10),
                      _buildDebugSimulatorToggleTile(),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Preview instructions',
                      style: TextStyle(
                        color: MapColors.text.withValues(alpha: 0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_previewInstructionCount(selected) == 0)
                      Text(
                        'No step previews available for this suggestion.',
                        style: TextStyle(
                          color: MapColors.text.withValues(alpha: 0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      ..._buildPreviewInstructionRows(selected),
                  ],
                ],
              ),
              if (selected != null)
                SheetScrollHint(scrollController: scrollController),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuggestedRoutesStrip() {
    const cardWidth = 182.0;
    const cardSpacing = 6.0;
    const trailingPadding = 36.0;

    return Stack(
      children: [
        ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(right: trailingPadding),
          itemCount: _routeSuggestions.length,
          separatorBuilder: (context, index) =>
              const SizedBox(width: cardSpacing),
          itemBuilder: (context, index) {
            return SizedBox(
              width: cardWidth,
              child: _buildSuggestionCard(
                _routeSuggestions[index],
                index: index,
                isSelected: index == _selectedSuggestionIndex,
              ),
            );
          },
        ),
        if (_routeSuggestions.length > 1)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      _sheetSurfaceColor.withValues(alpha: 0),
                      _sheetSurfaceColor.withValues(alpha: 0.95),
                    ],
                  ),
                ),
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: MapColors.text.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestionCard(
    NavigateSuggestion suggestion, {
    required int index,
    required bool isSelected,
  }) {
    final accentColor = _accentColorForSuggestion(suggestion, index);
    final badgeColor = suggestion.label == NavigateSuggestionLabel.fastest
        ? MapColors.primary
        : accentColor;
    final badgeTextColor = _badgeTextColor(badgeColor);
    final badgeText = _routeBadgeText(suggestion, index);
    final rides = _rideCountForSuggestion(suggestion);
    final rideLabel = rides == 1 ? 'Ride' : 'Rides';
    final distance = _formatDistance(suggestion.totalDistanceMeters);
    final modeSummary = _modeSummaryForSuggestion(suggestion);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onSuggestionCardSelected(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 182,
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          decoration: BoxDecoration(
            color: _sheetSurfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? MapColors.text.withValues(alpha: 0.24)
                  : MapColors.text.withValues(alpha: 0.12),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: MapColors.text.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 70,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isSelected ? 1 : 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeTextColor,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$rides $rideLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected
                            ? MapColors.text
                            : MapColors.text.withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$distance - $modeSummary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected
                            ? MapColors.text.withValues(alpha: 0.82)
                            : MapColors.text.withValues(alpha: 0.66),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPreviewInstructionRows(NavigateSuggestion suggestion) {
    final widgets = <Widget>[];
    var rendered = 0;
    for (final leg in suggestion.route.legs) {
      final previewText = _previewInstructionText(leg);
      if (previewText.isEmpty) continue;

      rendered += 1;
      if (rendered > 5) break;
      widgets.add(
        Padding(
          padding: EdgeInsets.only(bottom: rendered == 5 ? 0 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _iconForLegType(leg.type),
                size: 16,
                color: _colorForLeg(leg),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  previewText,
                  style: TextStyle(
                    color: MapColors.text.withValues(alpha: 0.83),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  String _previewInstructionText(NavigateLeg leg) {
    final distance = _formatDistance(leg.distanceMeters);
    switch (leg.type) {
      case NavigateLegType.walk:
        return 'Walk $distance';
      case NavigateLegType.jeepney:
        final label = _jeepneyPreviewLabel(leg);
        final base = label.isEmpty ? _labelForLegType(leg.type) : label;
        return '$base - $distance';
      case NavigateLegType.tricycle:
      case NavigateLegType.unknown:
        final routeName = leg.routeName.trim();
        final base = routeName.isNotEmpty
            ? routeName
            : _labelForLegType(leg.type);
        return '$base - $distance';
    }
  }

  String _jeepneyPreviewLabel(NavigateLeg leg) {
    final routeName = leg.routeName.trim();
    if (routeName.isEmpty) return '';

    final routeNumber = leg.routeNumber.trim();
    if (routeNumber.isNotEmpty) {
      final code = _formatRouteCode(routeNumber);
      return '$routeName ($code)';
    }

    if (_hasRouteNumberInName(routeName)) {
      return routeName;
    }

    final extracted = _extractRouteNumberFromName(routeName);
    if (extracted == null || extracted.isEmpty) return routeName;
    final code = _formatRouteCode(extracted);
    return '$routeName ($code)';
  }

  bool _hasRouteNumberInName(String name) {
    return RegExp(r'\broute\s*\w+\b', caseSensitive: false).hasMatch(name) ||
        RegExp(r'\bR\s*\d+\b', caseSensitive: false).hasMatch(name);
  }

  String? _extractRouteNumberFromName(String name) {
    final parenMatch = RegExp(
      r'\(\s*Route\s*([^)]+)\)',
      caseSensitive: false,
    ).firstMatch(name);
    if (parenMatch != null) return parenMatch.group(1)?.trim();

    final routeMatch = RegExp(
      r'\bRoute\s*([A-Za-z0-9-]+)\b',
      caseSensitive: false,
    ).firstMatch(name);
    if (routeMatch != null) return routeMatch.group(1)?.trim();

    final rMatch = RegExp(
      r'\bR\s*\d+\b',
      caseSensitive: false,
    ).firstMatch(name);
    if (rMatch != null) return rMatch.group(0)?.replaceAll(' ', '');

    return null;
  }

  String _formatRouteCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final rMatch = RegExp(
      r'^R\s*(\d+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (rMatch != null) return 'R${rMatch.group(1)}';

    final routeMatch = RegExp(
      r'^Route\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (routeMatch != null) {
      return _formatRouteCode(routeMatch.group(1)?.trim() ?? trimmed);
    }

    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return 'R$trimmed';
    }

    return trimmed;
  }

  Widget _buildRouteDetailsSheet() {
    final selected = _selectedSuggestion;
    if (selected == null) {
      return const SizedBox.shrink();
    }

    final legTimelineBlocks = _buildLegBlocks();

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _sheetDefaultSize,
      minChildSize: _sheetCollapsedSize,
      maxChildSize: _sheetMaxSize,
      snap: true,
      snapSizes: _sheetSnapSizes,
      builder: (context, scrollController) {
        return _SheetSurface(
          sheetController: _sheetController,
          scrollController: scrollController,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Route Details',
                      style: const TextStyle(
                        color: MapColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close and reset',
                    onPressed: _resetToExplore,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${_formatMinutes(selected.totalDurationMinutes)} - ${_formatDistance(selected.totalDistanceMeters)}',
                style: TextStyle(
                  color: MapColors.text.withValues(alpha: 0.72),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_activeLegIsolationIndex != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _showAllRouteSteps,
                  icon: const Icon(Icons.center_focus_strong_rounded),
                  label: const Text('Show all step-by-step'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    side: BorderSide(
                      color: MapColors.text.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...legTimelineBlocks,
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildLegBlocks({bool withCompletedState = false}) {
    final selected = _selectedSuggestion;
    if (selected == null) return const <Widget>[];

    final legTimelineBlocks = <Widget>[];
    final currentNavigationLegIndex = _currentNavigationLegIndex;
    var boardCountBeforeLeg = 0;
    var jeepStepNumber = 0;
    for (int i = 0; i < selected.route.legs.length; i++) {
      final leg = selected.route.legs[i];
      int? jeepNumber;
      if (leg.type == NavigateLegType.jeepney) {
        jeepStepNumber += 1;
        jeepNumber = jeepStepNumber;
      }
      legTimelineBlocks.add(
        _buildLegTimelineBlock(
          leg,
          index: i,
          isLast: i == selected.route.legs.length - 1,
          boardCountBeforeLeg: boardCountBeforeLeg,
          jeepStepNumber: jeepNumber,
          isIsolated: _activeLegIsolationIndex == i,
          isCurrent:
              withCompletedState &&
              currentNavigationLegIndex != null &&
              i == currentNavigationLegIndex,
          isCompleted:
              withCompletedState &&
              currentNavigationLegIndex != null &&
              i < currentNavigationLegIndex,
          onTap: () => _onLegTimelineStepTapped(i),
        ),
      );

      boardCountBeforeLeg += leg.instructions
          .where(
            (instruction) =>
                instruction.maneuverType == NavigateManeuverType.board,
          )
          .length;
    }
    return legTimelineBlocks;
  }

  Widget _buildLegTimelineBlock(
    NavigateLeg leg, {
    required int index,
    required bool isLast,
    required int boardCountBeforeLeg,
    required int? jeepStepNumber,
    required bool isIsolated,
    bool isCurrent = false,
    bool isCompleted = false,
    required VoidCallback onTap,
  }) {
    var boardCount = boardCountBeforeLeg;
    final baseLabel = leg.type == NavigateLegType.jeepney
        ? 'Jeep'
        : _labelForLegType(leg.type);
    final stepLabel = jeepStepNumber == null
        ? baseLabel
        : '$baseLabel $jeepStepNumber';
    final timelineColor = isCompleted
        ? MapColors.text.withValues(alpha: 0.26)
        : _timelineSubtleLineColor;
    final iconColor = isCompleted
        ? MapColors.text.withValues(alpha: 0.44)
        : MapColors.text;
    final titleColor = isCompleted
        ? MapColors.text.withValues(alpha: 0.48)
        : MapColors.text;
    final bodyColor = isCompleted
        ? MapColors.text.withValues(alpha: 0.42)
        : MapColors.text;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 38,
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? MapColors.text.withValues(alpha: 0.08)
                          : _colorForLeg(leg).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Icon(
                      _iconForLegType(leg.type),
                      size: 18,
                      color: iconColor,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: timelineColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: _sheetSurfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isIsolated || isCurrent)
                            ? MapColors.primary.withValues(alpha: 0.55)
                            : MapColors.text.withValues(alpha: 0.1),
                        width: (isIsolated || isCurrent) ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                stepLabel,
                                style: TextStyle(
                                  color: titleColor,
                                  fontSize: 15,
                                  fontWeight: isCompleted
                                      ? FontWeight.w700
                                      : FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              _formatMinutes(leg.durationMinutes),
                              style: TextStyle(
                                color: bodyColor.withValues(alpha: 0.74),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (leg.routeName.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _legRouteDisplayName(leg),
                            style: TextStyle(
                              color: bodyColor.withValues(alpha: 0.84),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (leg.type == NavigateLegType.jeepney)
                          StickerGallery(
                            imageUrls:
                                _stickerUrlsByRouteId[leg.routeId] ?? const [],
                            height: 64,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDistance(leg.distanceMeters),
                          style: TextStyle(
                            color: bodyColor.withValues(alpha: 0.65),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isCompleted) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Completed',
                            style: TextStyle(
                              color: MapColors.text.withValues(alpha: 0.46),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else ...[
                          if (isCurrent) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Current step',
                              style: TextStyle(
                                color: MapColors.primary.withValues(
                                  alpha: 0.82,
                                ),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          if (leg.instructions.isEmpty)
                            Text(
                              'No detailed instructions for this leg.',
                              style: TextStyle(
                                color: MapColors.text.withValues(alpha: 0.68),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            for (int i = 0; i < leg.instructions.length; i++)
                              Builder(
                                builder: (context) {
                                  final instruction = leg.instructions[i];
                                  final isBoard =
                                      instruction.maneuverType ==
                                      NavigateManeuverType.board;
                                  final isTransferBoard =
                                      isBoard && boardCount > 0;

                                  if (isBoard) {
                                    boardCount += 1;
                                  }

                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: i == leg.instructions.length - 1
                                          ? 0
                                          : 8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          _iconForInstruction(
                                            leg: leg,
                                            instruction: instruction,
                                            isTransferBoard: isTransferBoard,
                                          ),
                                          size: 15,
                                          color: _colorForManeuver(
                                            instruction.maneuverType,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Text(
                                            instruction.text,
                                            style: TextStyle(
                                              color: bodyColor.withValues(
                                                alpha: 0.8,
                                              ),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              height: 1.33,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _legRouteDisplayName(NavigateLeg leg) {
    final routeName = leg.routeName.trim();
    if (routeName.isEmpty) return '';

    if (leg.type != NavigateLegType.jeepney) {
      return routeName;
    }

    final routeNumber = leg.routeNumber.trim();
    if (routeNumber.isNotEmpty) {
      return '${_formatRouteCode(routeNumber)} - $routeName';
    }

    return routeName;
  }

  String _labelForLegType(NavigateLegType type) {
    return switch (type) {
      NavigateLegType.walk => 'Walk',
      NavigateLegType.jeepney => 'Jeepney',
      NavigateLegType.tricycle => 'Tricycle',
      NavigateLegType.unknown => 'Transit',
    };
  }
}

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({
    required this.sheetController,
    required this.scrollController,
    required this.child,
  });

  final DraggableScrollableController sheetController;
  final ScrollController scrollController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MapColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: MapColors.text.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: MapColors.text.withValues(alpha: 0.13),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          SheetDragHandle(
            controller: sheetController,
            scrollController: scrollController,
            minChildSize: _sheetCollapsedSize,
            maxChildSize: _sheetMaxSize,
            snapSizes: _sheetSnapSizes,
            barWidth: 44,
            barHeight: 5,
            barColor: MapColors.text.withValues(alpha: 0.22),
            barBorderRadius: 999,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
