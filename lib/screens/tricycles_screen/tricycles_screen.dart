import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' hide Position;

import 'package:jippy_mobile/core/config/map_config.dart';
import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/data/map_data_loader.dart';
import 'package:jippy_mobile/models/map_layer_models.dart';
import 'package:jippy_mobile/models/routes_and_stations_data.dart';
import 'package:jippy_mobile/models/tricycle_region.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/loading_overlay.dart';
import 'package:jippy_mobile/screens/tricycles_screen/widgets/tricycles_regions_list.dart';
import 'package:jippy_mobile/services/location_service.dart';
import 'package:jippy_mobile/utils/map_coords.dart';
import 'package:jippy_mobile/utils/route_color_parser.dart';
import 'package:jippy_mobile/widgets/jippy_map_canvas.dart';
import 'package:jippy_mobile/widgets/map_location_control.dart';
import 'package:jippy_mobile/widgets/sheet_drag_handle.dart';
import 'package:jippy_mobile/widgets/tricycle_station_marker.dart';

const double _initialZoom = 12.0;

const double _regionFillOpacity = 0.25;

const double _drawerCollapsedSize = 0.16;
const double _drawerDefaultSize = 0.38;
const double _drawerMaxSize = 0.85;
const List<double> _drawerSnapSizes = <double>[
  _drawerCollapsedSize,
  _drawerDefaultSize,
  _drawerMaxSize,
];

bool _hasNetworkInterface(List<ConnectivityResult> results) {
  if (results.length == 1 && results.single == ConnectivityResult.none) {
    return false;
  }
  return true;
}

class TricyclesScreen extends StatefulWidget {
  const TricyclesScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<TricyclesScreen> createState() => _TricyclesScreenState();
}

class _TricyclesScreenState extends State<TricyclesScreen>
    with WidgetsBindingObserver {
  MapController? _mapController;
  final DraggableScrollableController _drawerController =
      DraggableScrollableController();
  final ValueNotifier<double> _drawerExtent =
      ValueNotifier<double>(_drawerDefaultSize);
  final LocationService _locationService = LocationService.instance;
  final Connectivity _connectivity = Connectivity();

  Position? _userPosition;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  LocationPermission? _locationPermission;
  bool _permissionChecked = false;
  bool _online = true;

  RoutesAndStationsData? _mapData;
  String? _mapStyle;
  bool _mapEverActive = false;
  bool _loadingData = true;
  String? _selectedRegionId;
  double _cameraZoom = _initialZoom;

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
    _mapEverActive = widget.isActive;
    _initConnectivity();
    _resolveMapStyle();
    _initLocation();
    _subscribeToServiceStatus();
    _loadMapData();
  }

  @override
  void didUpdateWidget(TricyclesScreen oldWidget) {
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
      _resolveMapStyle();
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
    _connectivitySubscription?.cancel();
    _drawerController.dispose();
    _drawerExtent.dispose();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final first = await _connectivity.checkConnectivity();
    if (!mounted) return;
    setState(() => _online = _hasNetworkInterface(first));
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) async {
      if (!mounted) return;
      final online = _hasNetworkInterface(results);
      if (online != _online) {
        setState(() => _online = online);
        await _resolveMapStyle();
      }
    });
  }

  Future<void> _resolveMapStyle() async {
    final style = await resolveMapStyle(
      primaryStyleUrl: MapConfig.routesStyleUrl,
      online: _online,
    );
    if (!mounted) return;
    setState(() => _mapStyle = style);
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

  void _onMapCreated(MapController controller) {
    _mapController = controller;
    _cameraZoom = controller.getCamera().zoom;
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
    final controller = _mapController;
    if (controller == null) return;
    controller.moveCamera(
      center: toGeographic(MapConfig.routesDefaultCenter),
      zoom: _initialZoom,
      padding: EdgeInsets.zero,
    );
    _cameraZoom = _initialZoom;
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

  Future<void> _fitPoints(List<LatLng> points) async {
    final controller = _mapController;
    if (controller == null) return;
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

  void _fitRegionBounds(TricycleRegion region) {
    unawaited(_fitPoints(_polygonPointsForRegion(region)));
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
    unawaited(_fitPoints(points));
  }

  List<MapPolygonSpec> get _regionPolygons {
    final polygons = <MapPolygonSpec>[];
    for (final region in _visibleRegions) {
      if (!region.canRenderPolygon) continue;
      final points = _polygonPointsForRegion(region);
      if (points.length < 3) continue;

      final regionColor = parseRouteColor(region.regionColor);

      polygons.add(
        MapPolygonSpec(
          points: points,
          fillColor: regionColor.withValues(alpha: _regionFillOpacity),
          outlineColor: regionColor,
        ),
      );
    }
    return polygons;
  }

  List<MapWidgetMarkerSpec> get _stationMarkers {
    final markers = <MapWidgetMarkerSpec>[];
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
                      polygons: _regionPolygons,
                      widgetMarkers: _stationMarkers,
                    )
                  else
                    const ColoredBox(color: MapColors.background),
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
