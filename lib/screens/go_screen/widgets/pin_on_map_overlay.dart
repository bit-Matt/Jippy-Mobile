import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

/// Dims the routes map slightly and shows a center crosshair plus confirm for pin placement.
///
/// Touches pass through to the map so the user can pan; only the bottom bar captures taps.
class PinOnMapOverlay extends StatelessWidget {
  const PinOnMapOverlay({
    super.key,
    required this.title,
    required this.onCancel,
    required this.onConfirm,
  });

  final String title;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
              ),
            ),
          ),
        ),
        Center(
          child: IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add,
                  size: 48,
                  color: MapColors.primary.withValues(alpha: 0.95),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MapColors.text.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pan the map to move the pin',
                  style: TextStyle(
                    color: MapColors.text.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(16),
            color: MapColors.background,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  TextButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: onConfirm,
                    child: const Text('Confirm pin'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
