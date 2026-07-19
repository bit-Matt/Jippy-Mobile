import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Floating map control that tracks the bottom drawer's top edge and indicates
/// whether user location is on or off.
///
/// When location is on, renders a circular recenter / follow button.
/// When location is off, briefly expands a banner then collapses it into a
/// tappable [Icons.location_off] icon.
class MapLocationControl extends StatefulWidget {
  const MapLocationControl({
    super.key,
    required this.drawerExtent,
    required this.followClampExtent,
    required this.locationOn,
    required this.isFollowing,
    required this.onRecenter,
    required this.onEnableLocation,
    this.offMessage = 'Location is off',
    this.bottomGap = 12,
    this.right = 16,
  });

  /// Current fractional height of the bottom drawer (0 when no drawer).
  final ValueListenable<double> drawerExtent;

  /// Drawer extent at which the control stops following upward movement.
  final double followClampExtent;

  final bool locationOn;
  final bool isFollowing;
  final VoidCallback onRecenter;
  final VoidCallback onEnableLocation;
  final String offMessage;
  final double bottomGap;
  final double right;

  static const double _buttonSize = 48;

  /// Exposed so sibling map controls can align with this button.
  static const double buttonSize = _buttonSize;

  @override
  State<MapLocationControl> createState() => _MapLocationControlState();
}

class _MapLocationControlState extends State<MapLocationControl>
    with SingleTickerProviderStateMixin {
  static const Duration _expandDuration = Duration(milliseconds: 280);
  static const Duration _collapseDuration = Duration(milliseconds: 320);
  static const Duration _expandedPause = Duration(milliseconds: 1200);

  late final AnimationController _bannerController;
  Timer? _collapseTimer;
  int _offSequenceGeneration = 0;

  @override
  void initState() {
    super.initState();
    _bannerController = AnimationController(
      vsync: this,
      duration: _expandDuration,
      reverseDuration: _collapseDuration,
    );
    if (!widget.locationOn) {
      _startOffBannerSequence();
    }
  }

  @override
  void didUpdateWidget(MapLocationControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationOn && !widget.locationOn) {
      _startOffBannerSequence();
    } else if (!oldWidget.locationOn && widget.locationOn) {
      _cancelOffBannerSequence(resetCollapsed: true);
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  void _cancelOffBannerSequence({bool resetCollapsed = false}) {
    _offSequenceGeneration++;
    _collapseTimer?.cancel();
    _collapseTimer = null;
    _bannerController.stop();
    if (resetCollapsed) {
      _bannerController.value = 0;
    }
  }

  Future<void> _startOffBannerSequence() async {
    _cancelOffBannerSequence();
    final generation = ++_offSequenceGeneration;

    _bannerController.value = 0;
    await _bannerController.forward();
    if (!mounted || generation != _offSequenceGeneration || widget.locationOn) {
      return;
    }

    _collapseTimer = Timer(_expandedPause, () async {
      if (!mounted || generation != _offSequenceGeneration || widget.locationOn) {
        return;
      }
      await _bannerController.reverse();
    });
  }

  double _bottomOffset(double screenHeight) {
    final clampedExtent = math.min(
      widget.drawerExtent.value,
      widget.followClampExtent,
    );
    return clampedExtent * screenHeight + widget.bottomGap;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.drawerExtent,
      builder: (context, extent, child) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        return Positioned(
          right: widget.right,
          bottom: _bottomOffset(screenHeight),
          child: widget.locationOn
              ? _LocationOnButton(
                  size: MapLocationControl._buttonSize,
                  isFollowing: widget.isFollowing,
                  onTap: widget.onRecenter,
                )
              : _LocationOffBanner(
                  controller: _bannerController,
                  message: widget.offMessage,
                  buttonSize: MapLocationControl._buttonSize,
                  onTap: widget.onEnableLocation,
                ),
        );
      },
    );
  }
}

class _LocationOnButton extends StatelessWidget {
  const _LocationOnButton({
    required this.size,
    required this.isFollowing,
    required this.onTap,
  });

  final double size;
  final bool isFollowing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      elevation: 2,
      shadowColor: colorScheme.shadow,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            isFollowing ? Icons.gps_fixed : Icons.gps_not_fixed,
            color: colorScheme.primary,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _LocationOffBanner extends StatelessWidget {
  const _LocationOffBanner({
    required this.controller,
    required this.message,
    required this.buttonSize,
    required this.onTap,
  });

  final AnimationController controller;
  final String message;
  final double buttonSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    const horizontalMargin = 16.0;
    final expandedWidth = math.min(
      280.0,
      screenWidth - horizontalMargin * 2,
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(controller.value);
        final width = lerpDouble(buttonSize, expandedWidth, progress)!;
        final textOpacity = progress.clamp(0.0, 1.0);

        return Material(
          color: colorScheme.surfaceContainerHigh,
          elevation: 2,
          shadowColor: colorScheme.shadow,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: width,
              height: buttonSize,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (textOpacity > 0.01)
                    Expanded(
                      child: Opacity(
                        opacity: textOpacity,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Text(
                            message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: Icon(
                      Icons.location_off,
                      color: colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
