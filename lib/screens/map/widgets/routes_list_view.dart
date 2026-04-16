import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/screens/map/widgets/route_list_item.dart';
import 'package:jippy_mobile/utils/route_color_parser.dart';

class RoutesListBody extends StatelessWidget {
  const RoutesListBody({
    super.key,
    required this.routes,
    required this.isLoading,
    required this.isFocusedMode,
    required this.isCompareMode,
    required this.selectedRouteIds,
    required this.onRouteTap,
    required this.onRouteDetailsTap,
    this.loadingState = const SizedBox.shrink(),
  });

  final List<JeepneyRoute> routes;
  final bool isLoading;
  final bool isFocusedMode;
  final bool isCompareMode;
  final Set<String> selectedRouteIds;
  final ValueChanged<JeepneyRoute> onRouteTap;
  final ValueChanged<JeepneyRoute> onRouteDetailsTap;
  final Widget loadingState;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return loadingState;
    }

    if (routes.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MapColors.primary.withValues(alpha: 0.18)),
          color: MapColors.background,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: const Text(
          'No routes available right now.',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final selectedRoutes = (isFocusedMode && isCompareMode)
        ? routes.where((route) => selectedRouteIds.contains(route.id)).toList()
        : const <JeepneyRoute>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isFocusedMode && isCompareMode) ...[
          const Text(
            'Selected Routes',
            style: TextStyle(
              color: MapColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (selectedRoutes.isEmpty)
            Text(
              'No routes selected.',
              style: TextStyle(
                color: MapColors.text.withValues(alpha: 0.65),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final route in selectedRoutes)
                  FilterChip(
                    label: Text(
                      route.routeNumber.trim().isEmpty
                          ? route.routeName
                          : route.routeNumber.trim(),
                    ),
                    selected: true,
                    onSelected: (_) => onRouteTap(route),
                    showCheckmark: true,
                    selectedColor:
                        parseRouteColor(route.routeColor).withValues(alpha: 0.18),
                    checkmarkColor: parseRouteColor(route.routeColor),
                    labelStyle: TextStyle(
                      color: parseRouteColor(route.routeColor),
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: parseRouteColor(route.routeColor).withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
        ],
        const Text(
          'All Routes',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (int index = 0; index < routes.length; index++) ...[
          RouteListItem(
            route: routes[index],
            isSelected: isFocusedMode && selectedRouteIds.contains(routes[index].id),
            onTap: () => onRouteTap(routes[index]),
            onDetailsTap: () => onRouteDetailsTap(routes[index]),
          ),
          if (index < routes.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class RoutesListView extends StatelessWidget {
  const RoutesListView({
    super.key,
    required this.scrollController,
    required this.header,
    required this.body,
  });

  final ScrollController scrollController;
  final Widget header;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('routes-list-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        header,
        const SizedBox(height: 16),
        body,
        const SizedBox(height: 16),
      ],
    );
  }
}
