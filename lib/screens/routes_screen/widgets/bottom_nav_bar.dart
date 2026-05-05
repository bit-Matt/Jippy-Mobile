import 'package:flutter/material.dart';

import '../../../core/theme/map_colors.dart';

/// Bottom navigation strip for the routes map screen (Map / Routes / Settings).
class MapBottomNavBar extends StatelessWidget {
  const MapBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        bottomPadding > 0 ? bottomPadding : 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            index: 0,
            icon: Icons.map_outlined,
            label: 'Map',
            selectedIndex: selectedIndex,
            onSelected: onItemSelected,
          ),
          _NavItem(
            index: 1,
            icon: Icons.alt_route,
            label: 'Routes',
            selectedIndex: selectedIndex,
            onSelected: onItemSelected,
          ),
          _NavItem(
            index: 3,
            icon: Icons.person_outline,
            label: 'Settings',
            selectedIndex: selectedIndex,
            onSelected: onItemSelected,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int index;
  final IconData icon;
  final String label;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = selectedIndex == index;
    final color = selected
        ? MapColors.primary
        : MapColors.text.withValues(alpha: 0.35);
    return InkWell(
      onTap: () => onSelected(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
