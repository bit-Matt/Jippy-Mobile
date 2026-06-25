import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

class RoutesHeader extends StatelessWidget {
  const RoutesHeader({
    super.key,
    required this.isCompareMode,
    required this.showStations,
    required this.onCompareModeChanged,
    required this.onShowStationsChanged,
  });

  final bool isCompareMode;
  final bool showStations;
  final ValueChanged<bool> onCompareModeChanged;
  final ValueChanged<bool> onShowStationsChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Routes',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilterChip(
              label: const Text('Compare Routes'),
              selected: isCompareMode,
              onSelected: onCompareModeChanged,
              showCheckmark: false,
              selectedColor: MapColors.accentColor.withValues(alpha: 0.18),
              checkmarkColor: MapColors.accentColor,
              labelStyle: TextStyle(
                color: isCompareMode
                    ? MapColors.accentColor
                    : MapColors.text.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: isCompareMode
                    ? MapColors.accentColor.withValues(alpha: 0.7)
                    : MapColors.text.withValues(alpha: 0.18),
              ),
            ),
            FilterChip(
              label: const Text('Tricycle Stations'),
              selected: showStations,
              onSelected: onShowStationsChanged,
              showCheckmark: false,
              selectedColor: MapColors.accentColor.withValues(alpha: 0.18),
              checkmarkColor: MapColors.accentColor,
              labelStyle: TextStyle(
                color: showStations
                    ? MapColors.accentColor
                    : MapColors.text.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: showStations
                    ? MapColors.accentColor.withValues(alpha: 0.7)
                    : MapColors.text.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
