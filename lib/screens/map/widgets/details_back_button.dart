import 'package:flutter/material.dart';

import '../../../core/theme/map_colors.dart';

/// Padding so ink/hover fully covers icon + label on web/desktop.
class DetailsBackButton extends StatelessWidget {
  const DetailsBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: MapColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: const Icon(Icons.arrow_back, size: 16),
      label: const Text('Back', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
