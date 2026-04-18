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
import 'package:jippy_mobile/services/geocoding_service.dart';

/// Default center for the Go routes map: Iloilo City, Philippines.
final LatLng _iloiloCenter = LatLng(10.7202, 122.5621);

const double _initialZoom = 14.0;

const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

const String _vectorStyleUrl =
    'https://jippy.shinosawa-laboratories.dev/tileserver/style.json';

const String _userAgentPackageName = 'com.example.jippy_mobile';

const int _positionStreamDistanceFilterMeters = 8;

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
  final GeocodingService _geocoding = GeocodingService();
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

  bool _online = true;

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
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationPermission = null);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    setState(() => _locationPermission = permission);

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: _positionStreamDistanceFilterMeters,
      ),
    );
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
        ],
      ),
    );
  }
}
