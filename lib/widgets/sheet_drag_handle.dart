import 'dart:async';

import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';

/// Drag handle for [DraggableScrollableSheet] content that resizes the sheet
/// independently of any nested scroll view. Useful when the user has scrolled
/// deep inside the sheet and still wants to collapse it from the handle.
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({
    super.key,
    required this.controller,
    required this.minChildSize,
    required this.maxChildSize,
    required this.snapSizes,
    this.scrollController,
    this.topPadding = 12,
    this.bottomPadding = 10,
    this.hitAreaHeight = 32,
    this.barWidth = 78,
    this.barHeight = 4,
    this.barColor,
    this.barBorderRadius = 2,
  });

  final DraggableScrollableController controller;
  final ScrollController? scrollController;
  final double minChildSize;
  final double maxChildSize;
  final List<double> snapSizes;
  final double topPadding;
  final double bottomPadding;
  final double hitAreaHeight;
  final double barWidth;
  final double barHeight;
  final Color? barColor;
  final double barBorderRadius;

  double _nearestSnapSize(double size) {
    var nearest = snapSizes.first;
    var minDistance = (nearest - size).abs();
    for (final snap in snapSizes.skip(1)) {
      final distance = (snap - size).abs();
      if (distance < minDistance) {
        minDistance = distance;
        nearest = snap;
      }
    }
    return nearest;
  }

  void _resetScrollIfCollapsed(double targetSize) {
    final scroll = scrollController;
    if (scroll == null || !scroll.hasClients) return;
    if ((targetSize - minChildSize).abs() > 0.01) return;
    if (scroll.offset <= 0) return;
    scroll.jumpTo(0);
  }

  Future<void> _animateTo(double targetSize) {
    if (!controller.isAttached) return Future<void>.value();
    _resetScrollIfCollapsed(targetSize);
    return controller.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final resolvedBarColor =
        barColor ?? MapColors.text.withValues(alpha: 0.3);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: topPadding),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            if (!controller.isAttached) return;
            final delta = details.primaryDelta ?? 0;
            final newSize = (controller.size - delta / screenHeight)
                .clamp(minChildSize, maxChildSize);
            controller.jumpTo(newSize);
          },
          onVerticalDragEnd: (details) {
            if (!controller.isAttached) return;

            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 700) {
              unawaited(_animateTo(minChildSize));
              return;
            }
            if (velocity < -700) {
              unawaited(_animateTo(maxChildSize));
              return;
            }

            unawaited(_animateTo(_nearestSnapSize(controller.size)));
          },
          child: SizedBox(
            width: double.infinity,
            height: hitAreaHeight,
            child: Center(
              child: Container(
                width: barWidth,
                height: barHeight,
                decoration: BoxDecoration(
                  color: resolvedBarColor,
                  borderRadius: BorderRadius.circular(barBorderRadius),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: bottomPadding),
      ],
    );
  }
}
