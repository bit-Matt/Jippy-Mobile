import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/models/tricycle_region.dart';
import 'package:jippy_mobile/utils/route_color_parser.dart';

class TricyclesRegionsList extends StatelessWidget {
  const TricyclesRegionsList({
    super.key,
    required this.scrollController,
    required this.regions,
    required this.isLoading,
    required this.isFocusedMode,
    required this.selectedRegionId,
    required this.onRegionTap,
    required this.onShowAllRegions,
  });

  final ScrollController scrollController;
  final List<TricycleRegion> regions;
  final bool isLoading;
  final bool isFocusedMode;
  final String? selectedRegionId;
  final ValueChanged<TricycleRegion> onRegionTap;
  final VoidCallback onShowAllRegions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const Text(
          'Tricycle Regions',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 16),
        if (!isLoading && regions.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  isFocusedMode ? 'Currently viewing' : 'All Regions',
                  style: const TextStyle(
                    color: MapColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isFocusedMode)
                TextButton(
                  onPressed: onShowAllRegions,
                  style: TextButton.styleFrom(
                    foregroundColor: MapColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Show All Regions'),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (regions.isEmpty)
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
              'No tricycle regions available right now.',
              style: TextStyle(
                color: MapColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          for (int index = 0; index < regions.length; index++) ...[
            _RegionListItem(
              region: regions[index],
              isSelected: regions[index].id == selectedRegionId,
              onTap: () => onRegionTap(regions[index]),
            ),
            if (index < regions.length - 1) const SizedBox(height: 10),
          ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _RegionListItem extends StatelessWidget {
  const _RegionListItem({
    required this.region,
    required this.isSelected,
    required this.onTap,
  });

  final TricycleRegion region;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final regionColor = parseRouteColor(region.regionColor);
    final stationCount = region.stations.length;
    final stationLabel = stationCount == 1 ? '1 station' : '$stationCount stations';

    return Material(
      color: isSelected
          ? regionColor.withValues(alpha: 0.12)
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? regionColor.withValues(alpha: 0.65)
                  : MapColors.text.withValues(alpha: 0.12),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: regionColor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: regionColor, width: 1.5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      region.regionName.trim().isEmpty
                          ? 'Unnamed Region'
                          : region.regionName.trim(),
                      style: const TextStyle(
                        color: MapColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stationLabel,
                      style: TextStyle(
                        color: MapColors.text.withValues(alpha: 0.62),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: MapColors.text.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
