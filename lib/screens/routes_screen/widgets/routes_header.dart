import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Routes',
          style: theme.textTheme.headlineLarge?.copyWith(
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
            ),
            FilterChip(
              label: const Text('Tricycle Stations'),
              selected: showStations,
              onSelected: onShowStationsChanged,
              showCheckmark: false,
            ),
          ],
        ),
      ],
    );
  }
}
