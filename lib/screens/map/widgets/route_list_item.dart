import 'package:flutter/material.dart';

import '../../../core/theme/map_colors.dart';
import '../../../models/jeepney_route.dart';
import '../../../utils/route_color_parser.dart';

class RouteListItem extends StatelessWidget {
  const RouteListItem({
    super.key,
    required this.route,
    required this.isSelected,
    required this.onTap,
    this.onDetailsTap,
    this.overlapMode = false,
  });

  final JeepneyRoute route;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDetailsTap;
  final bool overlapMode;

  @override
  Widget build(BuildContext context) {
    final color = parseRouteColor(route.routeColor);
    final routeNumber = route.routeNumber.trim().isEmpty
        ? '--'
        : route.routeNumber.trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.18),
            width: isSelected ? 2 : 1,
          ),
          color: MapColors.background,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                routeNumber,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                route.routeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MapColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (!overlapMode && onDetailsTap != null)
              InkWell(
                onTap: onDetailsTap,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Details',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: color, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
