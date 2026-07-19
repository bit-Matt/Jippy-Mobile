import 'package:flutter/material.dart';

/// Floating hint shown at the bottom of a scrollable sheet when more content
/// exists below the current viewport.
class SheetScrollHint extends StatefulWidget {
  const SheetScrollHint({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  State<SheetScrollHint> createState() => _SheetScrollHintState();
}

class _SheetScrollHintState extends State<SheetScrollHint>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _bounceAnimation = Tween<double>(begin: 0, end: 5).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
    widget.scrollController.addListener(_updateVisibility);
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant SheetScrollHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_updateVisibility);
      widget.scrollController.addListener(_updateVisibility);
    }
    _scheduleVisibilityCheck();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    widget.scrollController.removeListener(_updateVisibility);
    super.dispose();
  }

  void _scheduleVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisibility());
  }

  void _setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    if (visible) {
      _bounceController.repeat(reverse: true);
    } else {
      _bounceController
        ..stop()
        ..value = 0;
    }
    setState(() {});
  }

  void _updateVisibility() {
    if (!mounted) return;

    final controller = widget.scrollController;
    if (!controller.hasClients) {
      _setVisible(false);
      return;
    }

    final position = controller.position;
    final hasMoreBelow = position.maxScrollExtent > 16;
    final nearTop = position.pixels <= 16;
    _setVisible(hasMoreBelow && nearTop);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurfaceVariant;
    final arrowColor = colorScheme.onSurfaceVariant;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Transform.translate(
          offset: const Offset(0, 6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Scroll for details',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                ),
                AnimatedBuilder(
                  animation: _bounceAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _bounceAnimation.value),
                      child: child,
                    );
                  },
                  child: Transform.translate(
                    offset: const Offset(0, -4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: arrowColor,
                        ),
                        Transform.translate(
                          offset: const Offset(0, -12),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: arrowColor.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
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
