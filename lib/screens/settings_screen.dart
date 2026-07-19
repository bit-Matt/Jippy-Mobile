import 'package:flutter/material.dart';

import '../models/entitlement.dart';
import '../services/entitlement_service.dart';
import 'offline_maps_screen.dart';
import 'report_screen.dart';

/// Settings screen displaying app configuration and action options.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top + 16;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 8),
      children: [
        Text(
          'Settings',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Maps',
          children: [
            ValueListenableBuilder<Entitlement>(
              valueListenable: EntitlementService.instance.listenable,
              builder: (context, entitlement, child) {
                final locked = !EntitlementService.instance.premiumUnlocked;
                return ListTile(
                  leading: Icon(Icons.map_outlined, color: colorScheme.primary),
                  title: const Text('Offline Map'),
                  subtitle: Text(
                    locked
                        ? 'Premium · download Iloilo map, routes & regions'
                        : 'Download Iloilo map, routes & regions',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (locked) ...[
                        const _ProBadge(),
                        const SizedBox(width: 4),
                      ],
                      Icon(
                        Icons.chevron_right,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            const OfflineMapsScreen(),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Support',
          children: [
            ListTile(
              leading: Icon(
                Icons.bug_report_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Report an Issue'),
              subtitle: const Text(
                'Help us improve Jippy with your feedback',
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const ReportScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 12,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            'PRO',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
          ),
        ],
      ),
    );
  }
}
