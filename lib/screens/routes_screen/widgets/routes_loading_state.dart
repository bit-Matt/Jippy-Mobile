import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

class RoutesLoadingState extends StatelessWidget {
  const RoutesLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MapColors.primary.withValues(alpha: 0.18)),
        color: MapColors.background,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Row(
        children: const [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading routes...',
              style: TextStyle(
                color: MapColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
