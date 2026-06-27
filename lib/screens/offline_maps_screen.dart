import 'package:flutter/material.dart';

import '../core/config/billing_config.dart';
import '../core/config/map_config.dart';
import '../core/theme/map_colors.dart';
import '../models/entitlement.dart';
import '../models/offline_map_status.dart';
import '../services/connectivity_service.dart';
import '../services/entitlement_service.dart';
import '../services/notification_service.dart';
import '../services/offline_map_service.dart';
import '../services/subscription_service.dart';
import 'widgets/paywall_sheet.dart';

/// Settings sub-screen for downloading and managing the Iloilo offline map.
class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final OfflineMapService _offlineMapService = OfflineMapService.instance;

  bool get _premiumUnlocked => EntitlementService.instance.premiumUnlocked;

  Future<void> _openPaywall() async {
    if (!mounted) return;
    await showPaywallSheet(context);
  }

  Future<void> _startDownload() async {
    if (!_premiumUnlocked) {
      await _openPaywall();
      return;
    }

    if (!ConnectivityService.instance.isOnline.value) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to the internet to download the offline map.'),
        ),
      );
      return;
    }

    await NotificationService.instance.requestPermissions();

    if (!mounted) return;
    final pixelDensity = MediaQuery.devicePixelRatioOf(context);
    await _offlineMapService.downloadIloiloRegion(pixelDensity: pixelDensity);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete offline map?'),
        content: const Text(
          'This removes downloaded map tiles, routes, regions, and images '
          'from your device. You can download them again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _offlineMapService.deleteIloiloRegion();
    }
  }

  Future<void> _confirmRedownload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update offline map?'),
        content: const Text(
          'This deletes the current offline data and downloads a fresh copy '
          'of the map, routes, regions, and images. You need an internet connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _startDownload();
    }
  }

  Future<void> _confirmSimulateCancellation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Simulate subscription cancellation?'),
        content: const Text(
          'This clears your sandbox Premium subscription and deletes the '
          'downloaded offline map from your device. Internal testing only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await SubscriptionService.instance.simulateSandboxCancellation();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sandbox subscription cancelled. Offline map removed.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MapColors.background,
      appBar: AppBar(
        backgroundColor: MapColors.background,
        elevation: 0,
        foregroundColor: MapColors.text,
        title: const Text(
          'Offline Map',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ValueListenableBuilder<Entitlement>(
        valueListenable: EntitlementService.instance.listenable,
        builder: (context, entitlement, child) {
          return ValueListenableBuilder<OfflineMapStatus>(
            valueListenable: _offlineMapService.status,
            builder: (context, status, child) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  switch (status) {
                    OfflineMapUnsupported() => _buildUnsupportedCard(),
                    OfflineMapNotDownloaded() => _premiumUnlocked
                        ? _buildNotDownloadedCard()
                        : _buildPremiumLockedCard(),
                    OfflineMapDownloading() => _buildDownloadingCard(status),
                    OfflineMapDownloaded() => _buildDownloadedCard(),
                    OfflineMapError() => _buildErrorCard(status),
                  },
                  if (kPseudoBillingEnabled &&
                      (_premiumUnlocked || status is OfflineMapDownloaded)) ...[
                    const SizedBox(height: 24),
                    _buildSimulateCancellationSection(),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MapColors.primary.withValues(alpha: 0.18)),
        color: MapColors.background,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Iloilo City vector map',
            style: TextStyle(
              color: MapColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Download map tiles, jeepney routes, tricycle regions, and route '
            'images for offline use on the Routes and Tricycles screens. '
            'Map zoom levels ${MapConfig.iloiloOfflineMinZoom.toInt()}–'
            '${MapConfig.iloiloOfflineMaxZoom.toInt()}.',
            style: TextStyle(
              color: MapColors.text.withValues(alpha: 0.72),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnsupportedCard() {
    return _actionCard(
      child: Text(
        'Offline map downloads are not supported on this platform.',
        style: TextStyle(
          color: MapColors.text.withValues(alpha: 0.72),
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildNotDownloadedCard() {
    return _actionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No offline map downloaded yet.',
            style: TextStyle(
              color: MapColors.text.withValues(alpha: 0.72),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download map'),
            style: FilledButton.styleFrom(
              backgroundColor: MapColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumLockedCard() {
    return _actionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined,
                  color: MapColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Offline map is a Premium feature',
                  style: TextStyle(
                    color: MapColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Subscribe to download map tiles, jeepney routes, tricycle regions, '
            'and route images for use without a connection.',
            style: TextStyle(
              color: MapColors.text.withValues(alpha: 0.72),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openPaywall,
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Unlock with Premium'),
            style: FilledButton.styleFrom(
              backgroundColor: MapColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadingCard(OfflineMapDownloading status) {
    final progress = status.progress;

    final phaseLabel = switch (status.phase) {
      OfflineDownloadPhase.routesData => 'Downloading routes, regions & images…',
      OfflineDownloadPhase.mapTiles => 'Downloading map tiles…',
    };

    final detailText = switch (status.phase) {
      OfflineDownloadPhase.routesData => status.routesImagesTotal > 0
          ? '${status.routesImagesDownloaded} / ${status.routesImagesTotal} images'
          : 'Fetching route data from server…',
      OfflineDownloadPhase.mapTiles => status.totalTiles > 0
          ? '${status.loadedTiles} / ${status.totalTiles} tiles · '
                '${_formatBytes(status.loadedBytes)}'
          : '${_formatBytes(status.loadedBytes)} downloaded',
    };

    return _actionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            progress != null
                ? '${(progress * 100).round()}% complete'
                : 'Downloading…',
            style: const TextStyle(
              color: MapColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            phaseLabel,
            style: TextStyle(
              color: MapColors.text.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: MapColors.primary.withValues(alpha: 0.15),
            color: MapColors.primary,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            detailText,
            style: TextStyle(
              color: MapColors.text.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can leave this screen — download continues in the background.',
            style: TextStyle(
              color: MapColors.text.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadedCard() {
    return _actionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MapColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: MapColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Downloaded · routes, regions & map · zoom '
                    '${MapConfig.iloiloOfflineMinZoom.toInt()}–'
                    '${MapConfig.iloiloOfflineMaxZoom.toInt()}',
                    style: const TextStyle(
                      color: MapColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _confirmRedownload,
            icon: const Icon(Icons.refresh),
            label: const Text('Update map'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MapColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _confirmDelete,
            icon: Icon(Icons.delete_outline, color: MapColors.accent),
            label: Text(
              'Delete offline map',
              style: TextStyle(color: MapColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(OfflineMapError status) {
    return _actionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status.message,
            style: TextStyle(
              color: MapColors.accent,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry download'),
            style: FilledButton.styleFrom(
              backgroundColor: MapColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MapColors.primary.withValues(alpha: 0.18)),
        color: MapColors.background,
      ),
      child: child,
    );
  }

  Widget _buildSimulateCancellationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Internal testing only. Simulates cancelling a Premium subscription '
          'and removes all offline map data from this device.',
          style: TextStyle(
            color: MapColors.text.withValues(alpha: 0.55),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _confirmSimulateCancellation,
          icon: Icon(Icons.cancel_outlined, color: MapColors.accent),
          label: Text(
            'Simulate cancel subscription',
            style: TextStyle(color: MapColors.accent),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
