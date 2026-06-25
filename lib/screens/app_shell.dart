import 'package:flutter/material.dart';

import '../core/theme/map_colors.dart';
import 'go_screen/go_screen.dart';
import 'routes_screen/routes_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.onReady});

  final VoidCallback? onReady;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _bottomNavVisible = true;

  void _onBottomNavVisibilityChanged(bool visible) {
    if (_bottomNavVisible == visible) return;
    setState(() => _bottomNavVisible = visible);
  }

  void _onTabSelected(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      if (_selectedIndex == 0 && index != 0) {
        _bottomNavVisible = true;
      }
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      GoScreen(
        key: const ValueKey('go_screen'),
        isActive: _selectedIndex == 0,
        onReady: widget.onReady,
        onBottomNavVisibilityChanged: _onBottomNavVisibilityChanged,
      ),
      RoutesScreen(
        key: const ValueKey('routes_screen'),
        isActive: _selectedIndex == 1,
      ),
      const SettingsScreen(key: ValueKey('settings_screen')),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: _bottomNavVisible
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onTabSelected,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              elevation: 8,
              selectedItemColor: MapColors.primary,
              unselectedItemColor: MapColors.text.withValues(alpha: 0.45),
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.directions_car_filled_outlined),
                  label: 'Go',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.alt_route),
                  label: 'Routes',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Settings',
                ),
              ],
            )
          : null,
    );
  }
}
