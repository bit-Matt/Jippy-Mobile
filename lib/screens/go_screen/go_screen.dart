import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/screens/go_screen/go_state.dart';
import 'package:jippy_mobile/screens/go_screen/widgets/go_map_canvas.dart';
import 'package:jippy_mobile/screens/go_screen/widgets/go_search_bar.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/location_message.dart';
import 'package:jippy_mobile/services/geocoding_service.dart';
import 'package:jippy_mobile/services/location_service.dart';

/// Default center for the Go routes map: Iloilo City, Philippines.
final LatLng _iloiloCenter = LatLng(10.7202, 122.5621);

const double _initialZoom = 14.0;

const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

const String _vectorStyleUrl =
    'https://jippy.shinosawa-laboratories.dev/tileserver/style.json';

const String _userAgentPackageName = 'com.example.jippy_mobile';

const double _sheetInitialSize = 0.30;

const Color _cardSurfaceColor = Colors.white;
const Color _timelineSubtleLineColor = Color(0xFFCFD4DB);

bool _hasNetworkInterface(List<ConnectivityResult> results) {
  if (results.length == 1 && results.single == ConnectivityResult.none) {
    return false;
  }
  return true;
}

/// Map-first "Go" flow: search / pins for origin and destination (Steps 1–4 surface).
class GoScreen extends StatefulWidget {
  const GoScreen({super.key});

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
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocus = FocusNode();

  Style? _vectorStyle;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  GoSearchBarMode _searchMode = GoSearchBarMode.collapsed;
  GoPinTarget? _pinTarget;

  LatLng? _origin;
  LatLng? _destination;
  String _originLabel = '';
  bool _originLockedToMap = false;

  List<NominatimSearchHit> _suggestions = const [];
  String? _searchError;
  bool _nominatimBusy = false;
  bool _routePreviewLoading = false;
  String? _routePreviewSignature;

  Position? _userPosition;
  LocationPermission? _locationPermission;
  bool _permissionChecked = false;
  bool _hasCenteredToUserOnce = false;

  bool _online = true;
  late final List<_GoRouteOption> _routeOptions = _buildMockRouteOptions();
  static const List<int> _estimatedRidersByRoute = <int>[34, 27, 19];
  int _selectedRouteIndex = 0;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVectorStyle();
    _initLocation();
    _initConnectivity();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadVectorStyle();
    }
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
  }

  Future<void> _initLocation() async {
    final cachedPosition = _locationService.lastKnown;
    if (cachedPosition != null && mounted) {
      setState(() => _userPosition = cachedPosition);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerToUserOnce(cachedPosition);
      });
    }

    final serviceEnabled = await _locationService.isServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _permissionChecked = true;
        _locationPermission = null;
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
        if (!mounted) return;
        final journeyWasIncomplete = _origin == null || _destination == null;
        setState(() {
          _userPosition = position;
          if (!_originLockedToMap &&
              _locationPermission != LocationPermission.denied &&
              _locationPermission != LocationPermission.deniedForever) {
            _origin = LatLng(position.latitude, position.longitude);
            _originLabel = 'Your location';
          }
        });
        _centerToUserOnce(position);
        final journeyNowComplete = _origin != null && _destination != null;
        if (journeyWasIncomplete && journeyNowComplete) {
          _requestRoutePreviewIfComplete();
        }
      },
      onError: (_) {
        if (mounted) setState(() => _userPosition = null);
      },
    );
  }

  void _centerToUserOnce(Position position) {
    if (!mounted || _hasCenteredToUserOnce || _destination != null) return;
    _hasCenteredToUserOnce = true;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      _initialZoom,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _positionSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _destinationController.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  bool get _destinationOutOfArea {
    final d = _destination;
    if (d == null) return false;
    return !_geocoding.isWithinIloiloServiceArea(d);
  }

  bool get _gpsOriginAvailable {
    if (_userPosition == null) return false;
    final p = _locationPermission;
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  void _revertOriginToGps() {
    final pos = _userPosition;
    if (pos == null || !_gpsOriginAvailable) return;
    setState(() {
      _originLockedToMap = false;
      _origin = LatLng(pos.latitude, pos.longitude);
      _originLabel = 'Your location';
      _routePreviewSignature = null;
    });
    _requestRoutePreviewIfComplete();
  }

  void _openDestinationPinOnMap() {
    _expandSearch();
    setState(() => _pinTarget = GoPinTarget.destination);
  }

  void _handleMapTap(TapPosition _, LatLng point) {
    final role = _pinTarget;
    if (role == null) return;
    setState(() => _pinTarget = null);
    unawaited(_applyReverseLabel(point, isOrigin: role == GoPinTarget.origin));
  }

  void _expandSearch() {
    setState(() => _searchMode = GoSearchBarMode.expanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _destinationFocus.requestFocus();
    });
  }

  void _collapseSearch() {
    setState(() {
      _searchMode = GoSearchBarMode.collapsed;
      _suggestions = const [];
      _pinTarget = null;
    });
    _destinationFocus.unfocus();
  }

  void _onDestinationQueryChanged(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestions = const [];
        _searchError = null;
        _nominatimBusy = false;
      });
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
            'Connection problem — please check your internet and try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = const [];
        _nominatimBusy = false;
        _searchError =
            'Connection problem — please check your internet and try again.';
      });
    }
  }

  Future<void> _applyReverseLabel(LatLng point, {required bool isOrigin}) async {
    setState(() => _searchError = null);
    try {
      final label = await _geocoding.reverseLabel(point);
      if (!mounted) return;
      setState(() {
        if (isOrigin) {
          _origin = point;
          _originLabel = label;
          _originLockedToMap = true;
        } else {
          _destination = point;
          _destinationController.text = label;
        }
      });
      _requestRoutePreviewIfComplete();
    } on GeocodingException {
      if (!mounted) return;
      setState(() {
        _searchError =
            'Connection problem — please check your internet and try again.';
        if (isOrigin) {
          _origin = point;
          _originLabel = 'Pinned location';
          _originLockedToMap = true;
        } else {
          _destination = point;
          _destinationController.text = 'Pinned location';
        }
      });
      _requestRoutePreviewIfComplete();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchError =
            'Connection problem — please check your internet and try again.';
        if (isOrigin) {
          _origin = point;
          _originLabel = 'Pinned location';
          _originLockedToMap = true;
        } else {
          _destination = point;
          _destinationController.text = 'Pinned location';
        }
      });
      _requestRoutePreviewIfComplete();
    }
  }

  void _onPickSuggestion(NominatimSearchHit hit) {
    setState(() {
      _destination = hit.point;
      _destinationController.text = hit.displayName;
      _suggestions = const [];
      _searchError = null;
    });
    _requestRoutePreviewIfComplete();
  }

  void _cancelMapPinMode() {
    setState(() => _pinTarget = null);
  }

  Future<void> _requestRoutePreviewIfComplete() async {
    final o = _origin;
    final d = _destination;
    if (o == null || d == null) {
      _routePreviewSignature = null;
      return;
    }
    final sig =
        '${o.latitude.toStringAsFixed(5)},${o.longitude.toStringAsFixed(5)}|'
        '${d.latitude.toStringAsFixed(5)},${d.longitude.toStringAsFixed(5)}';
    if (_routePreviewSignature == sig) return;
    _routePreviewSignature = sig;

    setState(() => _routePreviewLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    _fitOriginDestination();
    setState(() => _routePreviewLoading = false);
  }

  void _fitOriginDestination() {
    final o = _origin;
    final d = _destination;
    if (o == null || d == null) return;
    final bounds = LatLngBounds.fromPoints([o, d]);
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

  void _onRouteSelected(int index) {
    if (_selectedRouteIndex == index) return;
    setState(() => _selectedRouteIndex = index);
  }

  String _etaText(BuildContext context) {
    final route = _routeOptions[_selectedRouteIndex];
    final arrival = DateTime.now().add(Duration(minutes: route.minutes));
    final time = TimeOfDay.fromDateTime(arrival);
    final formattedTime = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(time, alwaysUse24HourFormat: false);
    return 'Estimated arrival: $formattedTime';
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
              userPosition: userLatLng,
              origin: _origin,
              destination: _destination,
              osmTileUrl: _osmTileUrl,
              userAgentPackageName: _userAgentPackageName,
            ),
          ),
          GoRecenterButton(
            userPosition: _userPosition,
            mapController: _mapController,
          ),
          GoSearchBar(
            mode: _searchMode,
            onCollapsedTap: _expandSearch,
            onCollapseExpanded: _collapseSearch,
            originLabel: _originLabel,
            onOriginRowTap: () {
              _expandSearch();
              setState(() => _pinTarget = GoPinTarget.origin);
            },
            showRevertOriginToGps: _originLockedToMap && _gpsOriginAvailable,
            onRevertOriginToGps: _revertOriginToGps,
            onDestinationMapPinTap: _openDestinationPinOnMap,
            destinationController: _destinationController,
            destinationFocusNode: _destinationFocus,
            onDestinationTextChanged: _onDestinationQueryChanged,
            suggestions: _suggestions,
            onSuggestionTap: _onPickSuggestion,
            searchError: _searchError,
            showOutOfAreaDisclaimer: _destinationOutOfArea,
            isSearchingNominatim: _nominatimBusy,
            routePreviewLoading: _routePreviewLoading,
            mapPinAwaitingTap: _pinTarget,
            onCancelMapPinMode: _cancelMapPinMode,
          ),
          if (_searchMode == GoSearchBarMode.collapsed && _destination != null)
            _buildDraggableSheet(_routeOptions[_selectedRouteIndex]),
          if (_permissionChecked &&
              (_locationPermission == LocationPermission.denied ||
                  _locationPermission == LocationPermission.deniedForever ||
                  _locationPermission == null))
            MapLocationMessage(
              message: _locationPermission == null
                  ? 'Location service is disabled.'
                  : 'Location permission denied. Enable it to see your position on the Go map.',
            ),
        ],
      ),
    );
  }

  Widget _buildDraggableSheet(_GoRouteOption selectedRoute) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _sheetInitialSize,
      minChildSize: 0.24,
      maxChildSize: 0.86,
      snap: true,
      snapSizes: const <double>[_sheetInitialSize, 0.8],
      builder: (context, scrollController) {
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
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: MapColors.text.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    Text(
                      'Follow these steps to reach ${selectedRoute.destinationName}',
                      style: const TextStyle(
                        color: MapColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.06,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Suggested Routes',
                      style: TextStyle(
                        color: MapColors.text.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSuggestedRoutesStrip(),
                    const SizedBox(height: 18),
                    Text(
                      _etaText(context),
                      style: TextStyle(
                        color: MapColors.text.withValues(alpha: 0.72),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (int i = 0; i < selectedRoute.steps.length; i++)
                      _buildTimelineStep(
                        selectedRoute.steps[i],
                        isLast: i == selectedRoute.steps.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuggestedRoutesStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < _routeOptions.length; i++) ...[
            _buildRouteCard(
              option: _routeOptions[i],
              index: i,
              isSelected: i == _selectedRouteIndex,
            ),
            if (i != _routeOptions.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteCard({
    required _GoRouteOption option,
    required int index,
    required bool isSelected,
  }) {
    final mutedText = MapColors.text.withValues(alpha: 0.66);
    final routeTypeLabel = option.badge;
    final cardColor = _cardSurfaceColor;
    final estimatedRiders = _estimatedRidersByRoute[index];
    final tagColor = option.badgeBackgroundColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onRouteSelected(index),
        child: Container(
          width: 176,
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
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
                height: 62,
                decoration: BoxDecoration(
                  color: option.pathColor.withValues(
                    alpha: isSelected ? 1 : 0.55,
                  ),
                  borderRadius: BorderRadius.circular(99),
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
                            color: tagColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            routeTypeLabel,
                            style: TextStyle(
                              color: option.badgeTextColor,
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
                      '$estimatedRiders Rides',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? MapColors.text : mutedText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${option.distanceLabel} - ${option.modeSummary}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected
                            ? MapColors.text.withValues(alpha: 0.82)
                            : mutedText,
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

  Widget _buildTimelineStep(_GoTimelineStep step, {required bool isLast}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 46,
              child: Column(
                children: [
                  _buildTimelineIcon(step),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: step.connector == _GoStepConnector.blueBold
                            ? 3
                            : 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: switch (step.connector) {
                            _GoStepConnector.blueBold => MapColors.primary,
                            _GoStepConnector.greyThin =>
                              _timelineSubtleLineColor,
                            _GoStepConnector.none => Colors.transparent,
                          },
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        color: MapColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.subtitle,
                      style: TextStyle(
                        color: MapColors.text.withValues(alpha: 0.75),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineIcon(_GoTimelineStep step) {
    switch (step.kind) {
      case _GoStepKind.walk:
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: MapColors.secondary.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Icon(
            Icons.directions_walk_rounded,
            color: MapColors.text,
            size: 18,
          ),
        );
      case _GoStepKind.board:
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: MapColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Icon(
            Icons.directions_car_filled_rounded,
            color: Colors.white,
            size: 18,
          ),
        );
      case _GoStepKind.alight:
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: MapColors.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Icon(
            Icons.directions_walk_rounded,
            color: MapColors.accent,
            size: 18,
          ),
        );
    }
  }
}

List<_GoRouteOption> _buildMockRouteOptions() {
  return const [
    _GoRouteOption(
      badge: 'FASTEST',
      minutes: 15,
      distanceLabel: '3.2 km',
      modeSummary: 'Walk + Jeep',
      destinationName: 'SM City Iloilo',
      pathColor: MapColors.primary,
      badgeBackgroundColor: MapColors.primary,
      badgeTextColor: Colors.white,
      polylinePoints: [
        LatLng(10.7188, 122.5605),
        LatLng(10.7205, 122.5619),
        LatLng(10.7227, 122.5642),
        LatLng(10.7249, 122.5670),
        LatLng(10.7262, 122.5694),
      ],
      steps: [
        _GoTimelineStep(
          kind: _GoStepKind.walk,
          connector: _GoStepConnector.greyThin,
          title: 'Walk to Savannah Central Terminal',
          subtitle: 'About 3 mins (240 m). Exit North Gate and turn left.',
        ),
        _GoTimelineStep(
          kind: _GoStepKind.board,
          connector: _GoStepConnector.blueBold,
          title: 'Board Savannah 2 Jeepney',
          subtitle: 'Board the jeep and proceed toward Diversion Road.',
        ),
        _GoTimelineStep(
          kind: _GoStepKind.alight,
          connector: _GoStepConnector.none,
          title: 'Alight at Diversion Crossing',
          subtitle: 'Proceed to the SM City direct-link loading area.',
        ),
      ],
    ),
    _GoRouteOption(
      badge: 'ALT',
      minutes: 18,
      distanceLabel: '3.5 km',
      modeSummary: 'Jeep',
      destinationName: 'SM City Iloilo',
      pathColor: MapColors.secondary,
      badgeBackgroundColor: MapColors.secondary,
      badgeTextColor: MapColors.text,
      polylinePoints: [
        LatLng(10.7188, 122.5605),
        LatLng(10.7199, 122.5625),
        LatLng(10.7218, 122.5650),
        LatLng(10.7238, 122.5678),
        LatLng(10.7256, 122.5706),
      ],
      steps: [
        _GoTimelineStep(
          kind: _GoStepKind.walk,
          connector: _GoStepConnector.greyThin,
          title: 'Walk to Diversion Link Stop',
          subtitle: 'About 4 mins (320 m). Follow the pedestrian lane.',
        ),
        _GoTimelineStep(
          kind: _GoStepKind.board,
          connector: _GoStepConnector.blueBold,
          title: 'Board Direct Jeepney',
          subtitle: 'Ride straight to the mall loop without transfer.',
        ),
        _GoTimelineStep(
          kind: _GoStepKind.alight,
          connector: _GoStepConnector.none,
          title: 'Alight at SM City Main Dropoff',
          subtitle: 'Walk 1 min to the main entrance near the transport hub.',
        ),
      ],
    ),
    _GoRouteOption(
      badge: 'ALT',
      minutes: 21,
      distanceLabel: '3.9 km',
      modeSummary: 'Walk + Tricycle',
      destinationName: 'SM City Iloilo',
      pathColor: MapColors.accent,
      badgeBackgroundColor: MapColors.accent,
      badgeTextColor: Colors.white,
      polylinePoints: [
        LatLng(10.7188, 122.5605),
        LatLng(10.7195, 122.5622),
        LatLng(10.7209, 122.5648),
        LatLng(10.7226, 122.5679),
        LatLng(10.7248, 122.5701),
      ],
      steps: [
        _GoTimelineStep(
          kind: _GoStepKind.walk,
          connector: _GoStepConnector.greyThin,
          title: 'Walk to Benigno Aquino Tricycle Bay',
          subtitle: 'About 4 mins (300 m). Cross at the pedestrian lane.',
        ),
        _GoTimelineStep(
          kind: _GoStepKind.board,
          connector: _GoStepConnector.blueBold,
          title: 'Ride Tricycle to Diversion Transfer Point',
          subtitle: 'Take a tricycle heading to Diversion Road junction.',
        ),
        _GoTimelineStep(
          kind: _GoStepKind.alight,
          connector: _GoStepConnector.none,
          title: 'Alight and walk to SM City Iloilo',
          subtitle: 'Walk 8 mins (650 m) to the mall transport entrance.',
        ),
      ],
    ),
  ];
}

enum _GoStepKind { walk, board, alight }

enum _GoStepConnector { none, greyThin, blueBold }

class _GoTimelineStep {
  const _GoTimelineStep({
    required this.kind,
    required this.connector,
    required this.title,
    required this.subtitle,
  });

  final _GoStepKind kind;
  final _GoStepConnector connector;
  final String title;
  final String subtitle;
}

class _GoRouteOption {
  const _GoRouteOption({
    required this.badge,
    required this.minutes,
    required this.distanceLabel,
    required this.modeSummary,
    required this.destinationName,
    required this.pathColor,
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
    required this.polylinePoints,
    required this.steps,
  });

  final String badge;
  final int minutes;
  final String distanceLabel;
  final String modeSummary;
  final String destinationName;
  final Color pathColor;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;
  final List<LatLng> polylinePoints;
  final List<_GoTimelineStep> steps;
}
