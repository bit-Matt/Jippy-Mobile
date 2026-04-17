import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/models/road_closure.dart';

enum MapPanelMode { routes, overlap, routeDetails, closureDetails }

class MapUiState {
  const MapUiState({
    this.panelMode = MapPanelMode.routes,
    this.isFocusedMode = false,
    this.isCompareMode = false,
    this.showStations = true,
    this.selectedRouteIds = const <String>{},
    this.selectedRoute,
    this.selectedClosure,
    this.overlappingRoutes = const <JeepneyRoute>[],
    this.returnToOverlappingRoutesAfterDetails = false,
  });

  final MapPanelMode panelMode;
  final bool isFocusedMode;
  final bool isCompareMode;
  final bool showStations;
  final Set<String> selectedRouteIds;
  final JeepneyRoute? selectedRoute;
  final RoadClosure? selectedClosure;
  final List<JeepneyRoute> overlappingRoutes;
  final bool returnToOverlappingRoutesAfterDetails;

  MapUiState copyWith({
    MapPanelMode? panelMode,
    bool? isFocusedMode,
    bool? isCompareMode,
    bool? showStations,
    Set<String>? selectedRouteIds,
    JeepneyRoute? selectedRoute,
    bool clearSelectedRoute = false,
    RoadClosure? selectedClosure,
    bool clearSelectedClosure = false,
    List<JeepneyRoute>? overlappingRoutes,
    bool? returnToOverlappingRoutesAfterDetails,
  }) {
    return MapUiState(
      panelMode: panelMode ?? this.panelMode,
      isFocusedMode: isFocusedMode ?? this.isFocusedMode,
      isCompareMode: isCompareMode ?? this.isCompareMode,
      showStations: showStations ?? this.showStations,
      selectedRouteIds: selectedRouteIds ?? this.selectedRouteIds,
      selectedRoute: clearSelectedRoute
          ? null
          : (selectedRoute ?? this.selectedRoute),
      selectedClosure: clearSelectedClosure
          ? null
          : (selectedClosure ?? this.selectedClosure),
      overlappingRoutes: overlappingRoutes ?? this.overlappingRoutes,
      returnToOverlappingRoutesAfterDetails:
          returnToOverlappingRoutesAfterDetails ??
          this.returnToOverlappingRoutesAfterDetails,
    );
  }
}
