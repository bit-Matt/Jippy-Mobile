import 'package:flutter/material.dart';

import '../core/theme/map_colors.dart';
import '../services/connectivity_service.dart';
import '../services/entitlement_service.dart';
import 'go_screen/go_screen.dart';
import 'routes_screen/routes_screen.dart';
import 'settings_screen.dart';
import 'tricycles_screen/tricycles_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.onReady});

  final VoidCallback? onReady;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _bottomNavVisible = true;
  bool _offlineReadySignaled = false;
  bool _offlineNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _syncTabIndexForConnectivity();
    ConnectivityService.instance.isOnline.addListener(_onConnectivityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _signalReadyIfOffline());
  }

  void _syncTabIndexForConnectivity() {
    final online = ConnectivityService.instance.isOnline.value;
    if (!online) {
      // Online indices: 0=Go, 1=Routes, 2=Tricycles, 3=Settings
      // Offline indices: 0=Routes, 1=Tricycles, 2=Settings
      if (_selectedIndex == 0) {
        _selectedIndex = 0; // Go → Routes
      } else {
        _selectedIndex = (_selectedIndex - 1).clamp(0, 2);
      }
      _bottomNavVisible = true;
    }
  }

  @override
  void dispose() {
    ConnectivityService.instance.isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _signalReadyIfOffline() {
    if (_offlineReadySignaled || !mounted) return;
    if (!ConnectivityService.instance.isOnline.value) {
      _offlineReadySignaled = true;
      widget.onReady?.call();
      _maybeShowOfflineNotice();
    }
  }

  void _maybeShowOfflineNotice() {
    if (_offlineNoticeShown || !mounted) return;
    if (ConnectivityService.instance.isOnline.value) return;
    if (EntitlementService.instance.premiumUnlocked) return;

    _offlineNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No internet connection'),
          content: const Text(
            'You are currently offline. Routes, tricycle regions, and offline '
            'features require a Premium subscription. Subscribe when you are '
            'back online to unlock offline access.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    final online = ConnectivityService.instance.isOnline.value;
    if (!online) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _signalReadyIfOffline());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (online) {
          // Offline → online: shift indices right to make room for Go at 0.
          _selectedIndex = (_selectedIndex + 1).clamp(0, 3);
        } else {
          // Online → offline: hide Go tab and remap indices.
          if (_selectedIndex == 0) {
            _selectedIndex = 0; // Go → Routes
          } else {
            _selectedIndex = (_selectedIndex - 1).clamp(0, 2);
          }
          _bottomNavVisible = true;
        }
      });
    });
  }

  void _onBottomNavVisibilityChanged(bool visible) {
    if (_bottomNavVisible == visible) return;
    setState(() => _bottomNavVisible = visible);
  }

  void _onTabSelected(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      final online = ConnectivityService.instance.isOnline.value;
      if (online && _selectedIndex == 0 && index != 0) {
        _bottomNavVisible = true;
      }
      _selectedIndex = index;
    });
  }

  void _onGoReady() {
    if (_offlineReadySignaled || !mounted) return;
    _offlineReadySignaled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectivityService.instance.isOnline,
      builder: (context, _) {
        final online = ConnectivityService.instance.isOnline.value;

        final pages = online
            ? <Widget>[
                GoScreen(
                  key: const ValueKey('go_screen'),
                  isActive: _selectedIndex == 0,
                  onReady: _onGoReady,
                  onBottomNavVisibilityChanged: _onBottomNavVisibilityChanged,
                ),
                RoutesScreen(
                  key: const ValueKey('routes_screen'),
                  isActive: _selectedIndex == 1,
                ),
                TricyclesScreen(
                  key: const ValueKey('tricycles_screen'),
                  isActive: _selectedIndex == 2,
                ),
                const SettingsScreen(key: ValueKey('settings_screen')),
              ]
            : <Widget>[
                RoutesScreen(
                  key: const ValueKey('routes_screen'),
                  isActive: _selectedIndex == 0,
                ),
                TricyclesScreen(
                  key: const ValueKey('tricycles_screen'),
                  isActive: _selectedIndex == 1,
                ),
                const SettingsScreen(key: ValueKey('settings_screen')),
              ];

        final navItems = online
            ? const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.directions_car_filled_outlined),
                  label: 'Go',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.alt_route),
                  label: 'Routes',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.moped_outlined),
                  label: 'Tricycles',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Settings',
                ),
              ]
            : const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.alt_route),
                  label: 'Routes',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.moped_outlined),
                  label: 'Tricycles',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Settings',
                ),
              ];

        final clampedIndex = _selectedIndex.clamp(0, pages.length - 1);

        return Scaffold(
          body: IndexedStack(index: clampedIndex, children: pages),
          bottomNavigationBar: _bottomNavVisible
              ? BottomNavigationBar(
                  currentIndex: clampedIndex,
                  onTap: _onTabSelected,
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.white,
                  elevation: 8,
                  selectedItemColor: MapColors.primary,
                  unselectedItemColor: MapColors.text.withValues(alpha: 0.45),
                  selectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                  items: navItems,
                )
              : null,
        );
      },
    );
  }
}
