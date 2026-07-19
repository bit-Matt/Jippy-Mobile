import 'package:flutter/material.dart';

import '../core/config/billing_config.dart';
import '../core/config/map_config.dart';
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
      appBar: AppBar(
        title: const Text('Offline Map'),
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
                  _buildInfoCard(context),
                  const SizedBox(height: 16),
                  switch (status) {
                    OfflineMapUnsupported() => _buildUnsupportedCard(context),
                    OfflineMapNotDownloaded() => _premiumUnlocked
                        ? _buildNotDownloadedCard()
                        : _buildPremiumLockedCard(context),
                    OfflineMapDownloading() =>
                      _buildDownloadingCard(context, status),
                    OfflineMapDownloaded() => _buildDownloadedCard(context),
                    OfflineMapError() => _buildErrorCard(context, status),
                  },
                  if (kPseudoBillingEnabled &&
                      (_premiumUnlocked || status is OfflineMapDownloaded)) ...[
                    const SizedBox(height: 24),
                    _buildSimulateCancellationSection(context),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Iloilo City vector map',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Download map tiles, jeepney routes, tricycle regions, and route '
              'images for offline use on the Routes and Tricycles screens. '
              'Map zoom levels ${MapConfig.iloiloOfflineMinZoom.toInt()}–'
              '${MapConfig.iloiloOfflineMaxZoom.toInt()}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedCard(BuildContext context) {
    return _ActionCard(
      child: Text(
        'Offline map downloads are not supported on this platform.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildNotDownloadedCard() {
    return _ActionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No offline map downloaded yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download map'),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumLockedCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _ActionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                color: colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Offline map is a Premium feature',
                  style: theme.textTheme.titleSmall?.copyWith(
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openPaywall,
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Unlock with Premium'),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadingCard(
    BuildContext context,
    OfflineMapDownloading status,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = status.progress;

    final phaseLabel = switch (status.phase) {
      OfflineDownloadPhase.routesData =>
        'Downloading routes, regions & images…',
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

    return _ActionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            progress != null
                ? '${(progress * 100).round()}% complete'
                : 'Downloading…',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            phaseLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            detailText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can leave this screen — download continues in the background.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadedCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _ActionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Downloaded · routes, regions & map · zoom '
                      '${MapConfig.iloiloOfflineMinZoom.toInt()}–'
                      '${MapConfig.iloiloOfflineMaxZoom.toInt()}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _confirmRedownload,
            icon: const Icon(Icons.refresh),
            label: const Text('Update map'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _confirmDelete,
            icon: Icon(Icons.delete_outline, color: colorScheme.error),
            label: Text(
              'Delete offline map',
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, OfflineMapError status) {
    final colorScheme = Theme.of(context).colorScheme;

    return _ActionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status.message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry download'),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulateCancellationSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Internal testing only. Simulates cancelling a Premium subscription '
          'and removes all offline map data from this device.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _confirmSimulateCancellation,
          icon: Icon(Icons.cancel_outlined, color: colorScheme.error),
          label: Text(
            'Simulate cancel subscription',
            style: TextStyle(color: colorScheme.error),
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
