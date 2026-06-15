import 'package:flutter/material.dart';

import 'package:jippy_mobile/services/trip_simulator_service.dart';

class DebugTripSimulatorOverlay extends StatefulWidget {
  const DebugTripSimulatorOverlay({
    super.key,
    required this.state,
    required this.simulatorAvailable,
    required this.onPlayPause,
    required this.onStep,
    required this.onJumpToNextStop,
    required this.onStop,
    required this.onSpeedChanged,
    required this.onDragDelta,
  });

  final TripSimulatorState state;
  final bool simulatorAvailable;
  final VoidCallback onPlayPause;
  final VoidCallback onStep;
  final VoidCallback onJumpToNextStop;
  final VoidCallback onStop;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<Offset> onDragDelta;

  @override
  State<DebugTripSimulatorOverlay> createState() =>
      _DebugTripSimulatorOverlayState();
}

class _DebugTripSimulatorOverlayState extends State<DebugTripSimulatorOverlay> {
  bool _expanded = true;

  static const _mono = TextStyle(
    color: Colors.white,
    fontFamily: 'monospace',
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => widget.onDragDelta(details.delta),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: _expanded ? _buildExpanded() : _buildCollapsed(),
      ),
    );
  }

  Widget _buildCollapsed() {
    return _DevShell(
      key: const ValueKey('debug-trip-sim-collapsed'),
      child: InkWell(
        onTap: () => setState(() => _expanded = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.state.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'SIM ${widget.state.speedMultiplier.toInt()}x',
                style: _mono.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded() {
    final current = widget.state.totalPoints == 0
        ? 0
        : widget.state.currentPointIndex + 1;
    return _DevShell(
      key: const ValueKey('debug-trip-sim-expanded'),
      child: SizedBox(
        width: 252,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '[DEV] Trip Simulator',
                      style: _mono.copyWith(fontSize: 13),
                    ),
                  ),
                  _IconDevButton(
                    tooltip: 'Minimize',
                    icon: Icons.remove,
                    onPressed: () => setState(() => _expanded = false),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 14),
              Text(
                widget.simulatorAvailable
                    ? 'Point $current / ${widget.state.totalPoints}'
                    : 'No route loaded',
                style: _mono.copyWith(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _IconDevButton(
                    tooltip: widget.state.isPlaying ? 'Pause' : 'Play route',
                    icon: widget.state.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    onPressed: widget.simulatorAvailable
                        ? widget.onPlayPause
                        : null,
                  ),
                  _IconDevButton(
                    tooltip: 'Step',
                    icon: Icons.skip_next,
                    onPressed: widget.simulatorAvailable ? widget.onStep : null,
                  ),
                  _IconDevButton(
                    tooltip: 'Jump to next stop',
                    icon: Icons.my_location,
                    onPressed: widget.simulatorAvailable
                        ? widget.onJumpToNextStop
                        : null,
                  ),
                  _IconDevButton(
                    tooltip: 'Stop simulator',
                    icon: Icons.stop,
                    onPressed: widget.simulatorAvailable ? widget.onStop : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _SpeedButton(
                    label: '1x',
                    selected: _isSelectedSpeed(1),
                    onPressed: widget.simulatorAvailable
                        ? () => widget.onSpeedChanged(1)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  _SpeedButton(
                    label: '5x',
                    selected: _isSelectedSpeed(5),
                    onPressed: widget.simulatorAvailable
                        ? () => widget.onSpeedChanged(5)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  _SpeedButton(
                    label: '20x',
                    selected: _isSelectedSpeed(20),
                    onPressed: widget.simulatorAvailable
                        ? () => widget.onSpeedChanged(20)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSelectedSpeed(double speed) {
    return (widget.state.speedMultiplier - speed).abs() < 0.01;
  }
}

class _DevShell extends StatelessWidget {
  const _DevShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      ),
    );
  }
}

class _IconDevButton extends StatelessWidget {
  const _IconDevButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      color: Colors.white,
      disabledColor: Colors.white30,
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 30),
        foregroundColor: selected ? Colors.black : Colors.white,
        backgroundColor: selected ? Colors.white : Colors.transparent,
        disabledForegroundColor: Colors.white30,
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
      child: Text(label),
    );
  }
}
