import 'package:flutter/material.dart';

import '../../../core/theme/map_colors.dart';

/// Floating pill-shaped search bar at top.
class SearchBarOverlay extends StatelessWidget {
  const SearchBarOverlay({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding, left: 16, right: 16),
        child: Material(
          elevation: 2,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(24),
          color: MapColors.background,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.search, color: MapColors.primary, size: 24),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: onTap,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Where do you want to go?',
                        style: TextStyle(
                          color: MapColors.text.withValues(alpha: 0.6),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.mic_none,
                    color: MapColors.text.withValues(alpha: 0.7),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
