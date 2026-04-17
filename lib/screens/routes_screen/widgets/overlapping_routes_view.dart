import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/details_back_button.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/route_list_item.dart';

class OverlappingRoutesView extends StatelessWidget {
  const OverlappingRoutesView({
    super.key,
    required this.scrollController,
    required this.routes,
    required this.selectedRouteIds,
    required this.onBackPressed,
    required this.onRouteTap,
  });

  final ScrollController scrollController;
  final List<JeepneyRoute> routes;
  final Set<String> selectedRouteIds;
  final VoidCallback onBackPressed;
  final ValueChanged<JeepneyRoute> onRouteTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('overlapping-routes-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'Overlapping Routes',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MapColors.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DetailsBackButton(onPressed: onBackPressed),
          ],
        ),
        const SizedBox(height: 16),
        if (routes.isEmpty)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MapColors.primary.withValues(alpha: 0.18),
              ),
              color: MapColors.background,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: const Text(
              'No overlapping routes for this tap.',
              style: TextStyle(
                color: MapColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          Column(
            children: [
              for (int index = 0; index < routes.length; index++) ...[
                RouteListItem(
                  route: routes[index],
                  isSelected: selectedRouteIds.contains(routes[index].id),
                  overlapMode: true,
                  onTap: () => onRouteTap(routes[index]),
                ),
                if (index < routes.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
