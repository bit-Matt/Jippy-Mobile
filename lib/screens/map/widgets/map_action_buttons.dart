import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/map_colors.dart';

/// Right-side map actions (layers placeholder and recenter on user).
class MapActionButtons extends StatelessWidget {
  const MapActionButtons({
    super.key,
    required this.userPosition,
    required this.mapController,
    this.onLayersTap,
  });

  final Position? userPosition;
  final MapController mapController;
  final VoidCallback? onLayersTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: MediaQuery.sizeOf(context).height * 0.34,
      child: Column(
        children: [
          _MapActionButton(
            icon: Icons.layers_outlined,
            onTap: onLayersTap ?? () {},
          ),
          const SizedBox(height: 12),
          _MapActionButton(
            icon: Icons.gps_fixed,
            iconColor: MapColors.primary,
            onTap: () {
              final position = userPosition;
              if (position == null) return;
              mapController.move(
                LatLng(position.latitude, position.longitude),
                mapController.camera.zoom,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MapColors.background,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: iconColor ?? MapColors.text.withValues(alpha: 0.75),
            size: 24,
          ),
        ),
      ),
    );
  }
}
