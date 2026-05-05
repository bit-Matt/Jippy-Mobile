import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

/// Compact hint shown under the search bar while waiting for a map tap to place a pin.
class GoMapPinInstructionBanner extends StatelessWidget {
  const GoMapPinInstructionBanner({
    super.key,
    required this.forOrigin,
    required this.onCancel,
    this.onUseCurrentLocation,
  });

  final bool forOrigin;
  final VoidCallback onCancel;
  final VoidCallback? onUseCurrentLocation;

  @override
  Widget build(BuildContext context) {
    final showUseCurrentLocation = forOrigin && onUseCurrentLocation != null;
    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      color: MapColors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.touch_app_outlined,
              color: MapColors.primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                forOrigin
                    ? 'Tap the routes map where you want your trip to start.'
                    : 'Tap the routes map where you want to go.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: MapColors.text.withValues(alpha: 0.88),
                ),
              ),
            ),
            if (showUseCurrentLocation)
              TextButton(
                onPressed: onUseCurrentLocation,
                child: const Text('Use my location'),
              ),
            TextButton(
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
