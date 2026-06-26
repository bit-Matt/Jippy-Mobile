import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/data/map_data_loader.dart';
import 'package:jippy_mobile/models/routes_and_stations_data.dart';
import 'package:jippy_mobile/models/tricycle_region.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/loading_overlay.dart';
import 'package:jippy_mobile/screens/tricycles_screen/widgets/tricycles_canvas.dart';
import 'package:jippy_mobile/screens/tricycles_screen/widgets/tricycles_regions_list.dart';
import 'package:jippy_mobile/services/location_service.dart';
import 'package:jippy_mobile/utils/route_color_parser.dart';
import 'package:jippy_mobile/widgets/map_location_control.dart';
import 'package:jippy_mobile/widgets/sheet_drag_handle.dart';
import 'package:jippy_mobile/widgets/tricycle_station_marker.dart';

/// Default center for the tricycles map: Iloilo City, Philippines.
final LatLng _tricyclesDefaultCenter = LatLng(10.7, 122.5521);

const double _initialZoom = 12.0;

const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

const String _vectorStyleUrl =
    'https://jippy.shinosawa-laboratories.dev/tileserver/style.json';

const String _userAgentPackageName = 'com.jippy.mobile';

const double _regionFillOpacity = 0.25;
const double _regionStrokeWidth = 2;

const double _drawerCollapsedSize = 0.16;
const double _drawerDefaultSize = 0.38;
const double _drawerMaxSize = 0.85;
const List<double> _drawerSnapSizes = <double>[
  _drawerCollapsedSize,
  _drawerDefaultSize,
  _drawerMaxSize,
];

class TricyclesScreen extends StatefulWidget {
  const TricyclesScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<TricyclesScreen> createState() => _TricyclesScreenState();
}

class _TricyclesScreenState extends State<TricyclesScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final DraggableScrollableController _drawerController =
      DraggableScrollableController();
  final ValueNotifier<double> _drawerExtent =
      ValueNotifier<double>(_drawerDefaultSize);
  final LocationService _locationService = LocationService.instance;

  Position? _userPosition;
  double? _compassHeading;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  StreamSubscription<double?>? _headingSubscription;
  LocationPermission? _locationPermission;
  bool _permissionChecked = false;

  RoutesAndStationsData? _mapData;
  Style? _vectorStyle;
  bool _loadingData = true;
  String? _selectedRegionId;

  bool get _isFocusedMode => _selectedRegionId != null;

  List<TricycleRegion> get _sortedRegions {
    final regions = List<TricycleRegion>.from(
      _mapData?.regions ?? const <TricycleRegion>[],
    )..sort(
        (a, b) => a.regionName.toLowerCase().compareTo(
          b.regionName.toLowerCase(),
        ),
      );
    return regions;
  }

  List<TricycleRegion> get _visibleRegions {
    final allRegions = _sortedRegions;
    if (_selectedRegionId == null) return allRegions;
    return allRegions
        .where((region) => region.id == _selectedRegionId)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVectorStyle();
    _initLocation();
    _subscribeToServiceStatus();
    _subscribeToHeading();
    _loadMapData();
  }

  @override
  void didUpdateWidget(TricyclesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _resetToDefaultView();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadVectorStyle();
      _loadMapData();
      _locationService.refresh();
      _initLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _headingSubscription?.cancel();
    _drawerController.dispose();
    _drawerExtent.dispose();
    super.dispose();
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

  Future<void> _loadMapData() async {
    if (!mounted) return;
    setState(() => _loadingData = true);
    try {
      RoutesAndStationsData data;
      try {
        data = await loadRoutesFromApi();
      } catch (_) {
        data = await loadSampleMapData();
      }
      if (!mounted) return;
      setState(() => _mapData = data);
      _completeLoadingAfterRender();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_isFocusedMode) {
          final region = _visibleRegions.firstOrNull;
          if (region != null) {
            _fitRegionBounds(region);
          }
        } else {
          _fitAllRegions();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _mapData = const RoutesAndStationsData(
          routes: [],
          stations: [],
          regions: [],
          closures: [],
        ),
      );
      _completeLoadingAfterRender();
    }
  }

  void _completeLoadingAfterRender() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _loadingData = false);
    });
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
      await _locationService.refresh();
      return;
    }

    _positionSubscription = _locationService.stream.listen(
      (Position position) {
        if (mounted) {
          setState(() => _userPosition = position);
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _userPosition = null);
        }
      },
    );
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
    if (position == null) return;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      _mapController.camera.zoom,
    );
  }

  void _resetToDefaultView() {
    setState(() => _selectedRegionId = null);
    _moveToDefaultMapView();
    _animateDrawerTo(_drawerDefaultSize);
  }

  void _showAllRegions() {
    setState(() => _selectedRegionId = null);
    _fitAllRegions();
    _animateDrawerTo(_drawerDefaultSize);
  }

  void _moveToDefaultMapView() {
    _mapController.move(_tricyclesDefaultCenter, _initialZoom);
  }

  void _focusRegion(TricycleRegion region) {
    setState(() => _selectedRegionId = region.id);
    _fitRegionBounds(region);
    _animateDrawerTo(_drawerDefaultSize);
  }

  List<LatLng> _polygonPointsForRegion(TricycleRegion region) {
    return region.orderedPoints
        .map((point) => LatLng(point.lat, point.lng))
        .toList();
  }

  void _fitPoints(List<LatLng> points) {
    if (points.isEmpty) {
      _moveToDefaultMapView();
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

  void _fitRegionBounds(TricycleRegion region) {
    _fitPoints(_polygonPointsForRegion(region));
  }

  void _fitAllRegions() {
    final points = <LatLng>[];
    for (final region in _mapData?.regions ?? const <TricycleRegion>[]) {
      if (!region.canRenderPolygon) continue;
      points.addAll(_polygonPointsForRegion(region));
    }
    if (points.isEmpty) {
      _moveToDefaultMapView();
      return;
    }
    _fitPoints(points);
  }

  List<Polygon<Object>> get _regionPolygons {
    final polygons = <Polygon<Object>>[];
    for (final region in _visibleRegions) {
      if (!region.canRenderPolygon) continue;
      final points = _polygonPointsForRegion(region);
      if (points.length < 3) continue;

      final regionColor = parseRouteColor(region.regionColor);

      polygons.add(
        Polygon<Object>(
          points: points,
          color: regionColor.withValues(alpha: _regionFillOpacity),
          borderColor: regionColor,
          borderStrokeWidth: _regionStrokeWidth,
        ),
      );
    }
    return polygons;
  }

  List<Marker> get _stationMarkers {
    final markers = <Marker>[];
    for (final region in _visibleRegions) {
      for (final station in region.stations) {
        markers.add(
          buildTricycleStationMarker(
            point: LatLng(station.lat, station.lon),
            onTap: () => _focusRegion(region),
          ),
        );
      }
    }
    return markers;
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

  @override
  Widget build(BuildContext context) {
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
                  TricyclesCanvas(
                    mapController: _mapController,
                    vectorStyle: _vectorStyle,
                    initialCenter: _tricyclesDefaultCenter,
                    initialZoom: _initialZoom,
                    regionPolygons: _regionPolygons,
                    stationMarkers: _stationMarkers,
                    userPosition: _userPosition == null
                        ? null
                        : LatLng(
                            _userPosition!.latitude,
                            _userPosition!.longitude,
                          ),
                    userHeading: _compassHeading,
                    userSpeedMps: _userPosition?.speed,
                    userAccuracyMeters: _userPosition?.accuracy,
                    osmTileUrl: _osmTileUrl,
                    userAgentPackageName: _userAgentPackageName,
                  ),
                  if (_loadingData) const LoadingOverlay(),
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
            DraggableScrollableSheet(
              controller: _drawerController,
              initialChildSize: _drawerDefaultSize,
              minChildSize: _drawerCollapsedSize,
              maxChildSize: _drawerMaxSize,
              snap: true,
              snapSizes: _drawerSnapSizes,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: MapColors.background,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      SheetDragHandle(
                        controller: _drawerController,
                        scrollController: scrollController,
                        minChildSize: _drawerCollapsedSize,
                        maxChildSize: _drawerMaxSize,
                        snapSizes: _drawerSnapSizes,
                      ),
                      Expanded(
                        child: TricyclesRegionsList(
                          scrollController: scrollController,
                          regions: _visibleRegions,
                          isLoading: _loadingData,
                          isFocusedMode: _isFocusedMode,
                          selectedRegionId: _selectedRegionId,
                          onRegionTap: _focusRegion,
                          onShowAllRegions: _showAllRegions,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
