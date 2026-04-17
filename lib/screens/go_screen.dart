import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme/map_colors.dart';

final LatLng _goInitialCenter = LatLng(10.7202, 122.5621);
const double _goInitialZoom = 13.8;
const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _userAgentPackageName = 'com.example.jippy_mobile';
const double _sheetInitialSize = 0.30;

const Color _cardSurfaceColor = Colors.white;
const Color _timelineSubtleLineColor = Color(0xFFCFD4DB);

class GoScreen extends StatefulWidget {
  const GoScreen({super.key});

  @override
  State<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends State<GoScreen> {
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  late final List<_GoRouteOption> _routeOptions = _buildMockRouteOptions();
  static const List<int> _estimatedRidersByRoute = <int>[34, 27, 19];
  int _selectedRouteIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitSelectedRoute();
    });
  }

  void _onRouteSelected(int index) {
    if (_selectedRouteIndex == index) return;
    setState(() {
      _selectedRouteIndex = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitSelectedRoute();
    });
  }

  void _fitSelectedRoute() {
    if (!mounted) return;

    final selected = _routeOptions[_selectedRouteIndex];
    if (selected.polylinePoints.length < 2) return;

    final bounds = LatLngBounds.fromPoints(selected.polylinePoints);
    final sheetSize = _sheetController.isAttached
        ? _sheetController.size
        : _sheetInitialSize;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomPadding =
        (screenHeight * sheetSize).clamp(180.0, 520.0).toDouble() + 28;

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.fromLTRB(28, 112, 28, bottomPadding),
        ),
      );
    } catch (_) {
      _mapController.move(bounds.center, _mapController.camera.zoom);
    }
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

  List<Polyline<Object>> _buildRoutePolylines() {
    final polylines = <Polyline<Object>>[];
    for (int i = 0; i < _routeOptions.length; i++) {
      final option = _routeOptions[i];
      final isSelected = i == _selectedRouteIndex;
      polylines.add(
        Polyline<Object>(
          points: option.polylinePoints,
          color: isSelected
              ? option.pathColor
              : MapColors.text.withValues(alpha: 0.16),
          strokeWidth: isSelected ? 5.2 : 3.2,
        ),
      );
    }
    return polylines;
  }

  List<Marker> _buildEndpointMarkers() {
    final selected = _routeOptions[_selectedRouteIndex];
    return [
      Marker(
        point: selected.polylinePoints.first,
        width: 54,
        height: 54,
        child: _endpointMarker(
          icon: Icons.trip_origin,
          color: MapColors.text,
          label: 'Start',
        ),
      ),
      Marker(
        point: selected.polylinePoints.last,
        width: 54,
        height: 54,
        child: _endpointMarker(
          icon: Icons.flag,
          color: selected.pathColor,
          label: 'End',
        ),
      ),
    ];
  }

  Widget _endpointMarker({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: MapColors.background,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: MapColors.text.withValues(alpha: 0.16),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _cardSurfaceColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = _routeOptions[_selectedRouteIndex];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _goInitialCenter,
                initialZoom: _goInitialZoom,
                backgroundColor: MapColors.background,
              ),
              children: [
                TileLayer(
                  urlTemplate: _osmTileUrl,
                  userAgentPackageName: _userAgentPackageName,
                ),
                PolylineLayer<Object>(polylines: _buildRoutePolylines()),
                MarkerLayer(markers: _buildEndpointMarkers()),
                RichAttributionWidget(
                  animationConfig: const ScaleRAWA(),
                  showFlutterMapAttribution: false,
                  attributions: const [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          _buildSearchPrompt(context),
          _buildDraggableSheet(selectedRoute),
        ],
      ),
    );
  }

  Widget _buildSearchPrompt(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + 10;

    return Positioned(
      top: topInset,
      left: 16,
      right: 16,
      child: Material(
        color: MapColors.background,
        elevation: 2,
        shadowColor: MapColors.text.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.search, color: MapColors.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Where do you want to go?',
                    style: TextStyle(
                      color: MapColors.text.withValues(alpha: 0.6),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.mic_none_rounded,
                  color: MapColors.text.withValues(alpha: 0.52),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
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
  }) : platformBadgeText = null,
       boardDurationText = null;

  final _GoStepKind kind;
  final _GoStepConnector connector;
  final String title;
  final String subtitle;
  final String? platformBadgeText;
  final String? boardDurationText;
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
