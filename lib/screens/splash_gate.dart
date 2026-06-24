import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/map_colors.dart';
import 'app_shell.dart';

/// Branded loading overlay shown while the map and core services initialize.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  static const _logoAsset = 'assets/icons/Jippy-App-LogoIcon.png';
  static const _maxWait = Duration(seconds: 6);
  static const _fadeDuration = Duration(milliseconds: 400);

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _appReady = false;
  bool _showOverlay = true;
  bool _fadeOut = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(SplashGate._maxWait, _dismissOverlay);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _onAppReady() {
    if (_appReady) return;
    _appReady = true;
    _timeoutTimer?.cancel();
    _dismissOverlay();
  }

  void _dismissOverlay() {
    if (!_showOverlay || !mounted) return;
    setState(() => _fadeOut = true);
    Future<void>.delayed(SplashGate._fadeDuration, () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final logoWidth = MediaQuery.sizeOf(context).width * 0.4;

    return Stack(
      fit: StackFit.expand,
      children: [
        AppShell(onReady: _onAppReady),
        if (_showOverlay)
          IgnorePointer(
            ignoring: _fadeOut,
            child: AnimatedOpacity(
              opacity: _fadeOut ? 0 : 1,
              duration: SplashGate._fadeDuration,
              child: ColoredBox(
                color: MapColors.background,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        SplashGate._logoAsset,
                        width: logoWidth,
                      ),
                      const SizedBox(height: 24),
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: MapColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
