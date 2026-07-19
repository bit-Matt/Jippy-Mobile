import 'package:flutter/material.dart';

import 'package:jippy_mobile/widgets/sheet_drag_handle.dart';

class MapBottomDrawer extends StatelessWidget {
  const MapBottomDrawer({
    super.key,
    required this.controller,
    required this.initialChildSize,
    required this.minChildSize,
    required this.maxChildSize,
    required this.snapSizes,
    required this.showingClosureDetails,
    required this.showingRouteDetails,
    required this.showingOverlappingRoutes,
    required this.closureDetailsViewBuilder,
    required this.routeDetailsViewBuilder,
    required this.overlappingRoutesViewBuilder,
    required this.routesListViewBuilder,
  });

  final DraggableScrollableController controller;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final List<double> snapSizes;
  final bool showingClosureDetails;
  final bool showingRouteDetails;
  final bool showingOverlappingRoutes;
  final Widget Function(ScrollController) closureDetailsViewBuilder;
  final Widget Function(ScrollController) routeDetailsViewBuilder;
  final Widget Function(ScrollController) overlappingRoutesViewBuilder;
  final Widget Function(ScrollController) routesListViewBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      snap: true,
      snapSizes: snapSizes,
      builder: (BuildContext context, ScrollController scrollController) {
        return Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SheetDragHandle(
                controller: controller,
                scrollController: scrollController,
                minChildSize: minChildSize,
                maxChildSize: maxChildSize,
                snapSizes: snapSizes,
              ),
              Expanded(
                child: _buildActivePanel(scrollController),
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
