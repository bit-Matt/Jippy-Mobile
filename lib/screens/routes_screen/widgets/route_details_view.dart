import 'package:flutter/material.dart';

import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/details_back_button.dart';
import 'package:jippy_mobile/widgets/sticker_gallery.dart';

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
    final theme = Theme.of(context);
    final detailText = (route != null && route!.routeDetails.trim().isNotEmpty)
        ? route!.routeDetails.trim()
        : 'No details available for this route.';

    return ListView(
      key: const ValueKey<String>('route-details-view'),
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
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
                  style: theme.textTheme.headlineSmall?.copyWith(
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
        StickerGallery(
          imageUrls: route?.imageUrls ?? const [],
          height: 150,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              detailText,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
