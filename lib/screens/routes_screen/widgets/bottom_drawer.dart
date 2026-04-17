import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

class MapBottomDrawer extends StatelessWidget {
  const MapBottomDrawer({
    super.key,
    required this.showingClosureDetails,
    required this.showingRouteDetails,
    required this.showingOverlappingRoutes,
    required this.closureDetailsViewBuilder,
    required this.routeDetailsViewBuilder,
    required this.overlappingRoutesViewBuilder,
    required this.routesListViewBuilder,
  });

  final bool showingClosureDetails;
  final bool showingRouteDetails;
  final bool showingOverlappingRoutes;
  final Widget Function(ScrollController) closureDetailsViewBuilder;
  final Widget Function(ScrollController) routeDetailsViewBuilder;
  final Widget Function(ScrollController) overlappingRoutesViewBuilder;
  final Widget Function(ScrollController) routesListViewBuilder;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.38,
      minChildSize: 0.34,
      maxChildSize: 0.74,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: MapColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 78,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MapColors.text.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _buildActivePanel(scrollController),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivePanel(ScrollController scrollController) {
    if (showingClosureDetails) {
      return KeyedSubtree(
        key: const ValueKey<String>('drawer-panel-closure-details'),
        child: closureDetailsViewBuilder(scrollController),
      );
    }
    if (showingRouteDetails) {
      return KeyedSubtree(
        key: const ValueKey<String>('drawer-panel-route-details'),
        child: routeDetailsViewBuilder(scrollController),
      );
    }
    if (showingOverlappingRoutes) {
      return KeyedSubtree(
        key: const ValueKey<String>('drawer-panel-overlap-routes'),
        child: overlappingRoutesViewBuilder(scrollController),
      );
    }
    return KeyedSubtree(
      key: const ValueKey<String>('drawer-panel-routes-list'),
      child: routesListViewBuilder(scrollController),
    );
  }
}
