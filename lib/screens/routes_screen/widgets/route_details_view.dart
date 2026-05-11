import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/details_back_button.dart';

class RouteDetailsView extends StatelessWidget {
  const RouteDetailsView({
    super.key,
    required this.scrollController,
    required this.route,
    required this.onBackPressed,
  });

  final ScrollController scrollController;
  final JeepneyRoute? route;
  final VoidCallback onBackPressed;

  @override
  Widget build(BuildContext context) {
    final detailText = (route != null && route!.routeDetails.trim().isNotEmpty)
        ? route!.routeDetails.trim()
      : 'No details available for this route.';

    return ListView(
      key: const ValueKey<String>('route-details-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  route?.routeName ?? 'Route details',
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
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: MapColors.primary.withValues(alpha: 0.18),
            ),
            color: MapColors.background,
          ),
          padding: const EdgeInsets.all(14),
          child: Text(
            detailText,
            style: const TextStyle(
              color: MapColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
