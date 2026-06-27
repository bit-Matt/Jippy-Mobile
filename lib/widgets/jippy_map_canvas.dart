import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' hide LengthUnit, Position;
// Transitive dependency of maplibre; used to detect VM test stub platform.
// ignore: depend_on_referenced_packages
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart'
    show MapLibrePlatform;

import 'package:jippy_mobile/core/config/map_config.dart';
import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/models/map_layer_models.dart';
import 'package:jippy_mobile/utils/map_coords.dart';
import 'package:jippy_mobile/widgets/map_user_location.dart';

/// Resolves the basemap style: remote vector URL when online or when an
/// offline region is available, bundled raster fallback otherwise.
Future<String> resolveMapStyle({
  required String primaryStyleUrl,
  required bool online,
  required bool hasOfflineRegion,
}) async {
  if (online || hasOfflineRegion) return primaryStyleUrl;
  return rootBundle.loadString(MapConfig.osmRasterStyleAsset);
}

/// Builds grouped [PolylineLayer]s from [MapPolylineSpec] list.
List<PolylineLayer> buildPolylineLayers(List<MapPolylineSpec> polylines) {
  final grouped = <String, List<Feature<LineString>>>{};
  final styles = <String, ({Color color, int width, List<int>? dashArray})>{};

  for (final polyline in polylines) {
    if (polyline.points.length < 2) continue;
    final dashKey = polyline.dashArray?.join('-') ?? 'solid';
    final key = '${polyline.color.toARGB32()}-${polyline.width}-$dashKey';
    styles[key] = (
      color: polyline.color,
      width: polyline.width,
      dashArray: polyline.dashArray,
    );
    grouped.putIfAbsent(key, () => <Feature<LineString>>[]).add(
      Feature(geometry: toLineString(polyline.points)),
    );
  }

  return grouped.entries
      .map((entry) {
        final style = styles[entry.key]!;
        return PolylineLayer(
          polylines: entry.value,
          color: style.color,
          width: style.width,
          dashArray: style.dashArray,
        );
      })
      .toList(growable: false);
}

/// Builds grouped [PolygonLayer]s from [MapPolygonSpec] list.
List<PolygonLayer> buildPolygonLayers(List<MapPolygonSpec> polygons) {
  final grouped = <String, List<Feature<Polygon>>>{};
  final styles = <String, ({Color fillColor, Color outlineColor})>{};

  for (final polygon in polygons) {
    if (polygon.points.length < 3) continue;
    final key =
        '${polygon.fillColor.toARGB32()}-${polygon.outlineColor.toARGB32()}';
    styles[key] = (
      fillColor: polygon.fillColor,
      outlineColor: polygon.outlineColor,
    );
    grouped.putIfAbsent(key, () => <Feature<Polygon>>[]).add(
      Feature(geometry: toPolygon(polygon.points)),
    );
  }

  return grouped.entries
      .map((entry) {
        final style = styles[entry.key]!;
        return PolygonLayer(
          polygons: entry.value,
          color: style.fillColor,
          outlineColor: style.outlineColor,
        );
      })
      .toList(growable: false);
}

List<CircleLayer> buildCircleLayers(List<MapCircleSpec> circles) {
  final grouped = <String, List<Feature<Point>>>{};
  final styles =
      <
        String,
        ({
          int radiusPixels,
          Color color,
          Color strokeColor,
          int strokeWidth,
        })
      >{};

  for (final circle in circles) {
    final key =
        '${circle.radiusPixels}-${circle.color.toARGB32()}-${circle.strokeColor.toARGB32()}-${circle.strokeWidth}';
    styles[key] = (
      radiusPixels: circle.radiusPixels,
      color: circle.color,
      strokeColor: circle.strokeColor,
      strokeWidth: circle.strokeWidth,
    );
    grouped.putIfAbsent(key, () => <Feature<Point>>[]).add(
      Feature(geometry: Point(toGeographic(circle.point))),
    );
  }

  return grouped.entries
      .map((entry) {
        final style = styles[entry.key]!;
        return CircleLayer(
          points: entry.value,
          radius: style.radiusPixels,
          color: style.color,
          strokeColor: style.strokeColor,
          strokeWidth: style.strokeWidth,
        );
      })
      .toList(growable: false);
}

/// Shared MapLibre canvas used by Go, Routes, and Tricycles screens.
class JippyMapCanvas extends StatefulWidget {
  const JippyMapCanvas({
    super.key,
    required this.style,
    required this.initialCenter,
    required this.initialZoom,
    required this.onMapCreated,
    this.onMapClick,
    this.onUserGesture,
    this.onStyleLoaded,
    this.polylines = const [],
    this.polygons = const [],
    this.widgetMarkers = const [],
    this.circles = const [],
    this.showUserLocation = true,
  });

  final String style;
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(MapController controller) onMapCreated;
  final void Function(LatLng point)? onMapClick;
  final VoidCallback? onUserGesture;
  final VoidCallback? onStyleLoaded;
  final List<MapPolylineSpec> polylines;
  final List<MapPolygonSpec> polygons;
  final List<MapWidgetMarkerSpec> widgetMarkers;
  final List<MapCircleSpec> circles;
  final bool showUserLocation;

  @override
  State<JippyMapCanvas> createState() => _JippyMapCanvasState();
}

class _JippyMapCanvasState extends State<JippyMapCanvas> {
  MapController? _controller;

  List<MapPolylineSpec>? _cachedPolylines;
  List<MapPolygonSpec>? _cachedPolygons;
  List<MapCircleSpec>? _cachedCircles;
  List<Layer<Feature<Geometry>>>? _cachedLayers;

  bool get _isMapLibrePlatformReady =>
      MapLibrePlatform.instance.runtimeType.toString() !=
      '_MapLibrePluginStub';

  @override
  void didUpdateWidget(covariant JippyMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style && _controller != null) {
      _controller!.setStyle(widget.style);
    }
  }

  void _handleEvent(MapEvent event) {
    switch (event) {
      case MapEventMapCreated():
        _controller = event.mapController;
        widget.onMapCreated(event.mapController);
      case MapEventStyleLoaded():
        widget.onStyleLoaded?.call();
      case MapEventStartMoveCamera():
        if (event.reason == CameraChangeReason.apiGesture) {
          widget.onUserGesture?.call();
        }
      case MapEventClick():
        widget.onMapClick?.call(toLatLng(event.point));
      default:
        break;
    }
  }

  bool _layerInputsUnchanged() {
    return _listItemsIdentical(_cachedPolylines, widget.polylines) &&
        _listItemsIdentical(_cachedPolygons, widget.polygons) &&
        _listItemsIdentical(_cachedCircles, widget.circles);
  }

  bool _listItemsIdentical<T>(List<T>? cached, List<T> next) {
    if (identical(cached, next)) return true;
    if (cached == null || cached.length != next.length) return false;
    for (var i = 0; i < cached.length; i++) {
      if (!identical(cached[i], next[i])) return false;
    }
    return true;
  }

  List<Layer<Feature<Geometry>>> _resolveLayers() {
    if (_cachedLayers != null && _layerInputsUnchanged()) {
      return _cachedLayers!;
    }

    _cachedPolylines = widget.polylines;
    _cachedPolygons = widget.polygons;
    _cachedCircles = widget.circles;
    _cachedLayers = <Layer<Feature<Geometry>>>[
      ...buildPolylineLayers(widget.polylines),
      ...buildPolygonLayers(widget.polygons),
      ...buildCircleLayers(widget.circles),
    ];
    return _cachedLayers!;
  }

  List<Marker> get _widgetMarkers => widget.widgetMarkers
      .map(
        (m) => Marker(
          point: toGeographic(m.point),
          size: m.size,
          alignment: m.alignment,
          child: m.child,
        ),
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (!_isMapLibrePlatformReady) {
      return const ColoredBox(color: MapColors.background);
    }

    return ColoredBox(
      color: MapColors.background,
      child: MapLibreMap(
        options: MapOptions(
          initStyle: widget.style,
          initCenter: toGeographic(widget.initialCenter),
          initZoom: widget.initialZoom,
        ),
        onEvent: _handleEvent,
        layers: _resolveLayers(),
        children: [
          if (_widgetMarkers.isNotEmpty) WidgetLayer(markers: _widgetMarkers),
          if (widget.showUserLocation) const MapUserLocationLayer(),
          const SourceAttribution(),
        ],
      ),
    );
  }
}
