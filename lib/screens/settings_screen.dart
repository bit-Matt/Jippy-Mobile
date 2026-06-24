import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/billing_config.dart';
import '../core/theme/map_colors.dart';
import '../models/entitlement.dart';
import '../services/entitlement_service.dart';
import '../services/subscription_service.dart';
import 'report_screen.dart';
import 'widgets/paywall_sheet.dart';

/// Settings screen displaying app configuration and action options.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 16;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 8),
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 16),
        const _PremiumSection(),
        const SizedBox(height: 24),
        _buildSettingsSection(
          title: 'Support',
          children: [
            _SettingsTile(
              icon: Icons.bug_report_outlined,
              title: 'Report an Issue',
              subtitle: 'Help us improve Jippy with your feedback',
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

Widget _buildSettingsSection({
  required String title,
  required List<Widget> children,
}) {
  return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: MapColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: MapColors.primary.withValues(alpha: 0.18),
            ),
            color: MapColors.background,
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: MapColors.text.withValues(alpha: 0.08),
                    indent: 0,
                    endIndent: 0,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

/// Individual settings menu item with icon, title, and subtitle.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: MapColors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: MapColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: MapColors.text.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: MapColors.text.withValues(alpha: 0.4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium subscription section: upgrade/restore when locked, status + manage
/// when active. Listens to [EntitlementService] so it reflects purchases live.
class _PremiumSection extends StatefulWidget {
  const _PremiumSection();

  @override
  State<_PremiumSection> createState() => _PremiumSectionState();
}

class _PremiumSectionState extends State<_PremiumSection> {
  StreamSubscription<String>? _messageSub;

  @override
  void initState() {
    super.initState();
    _messageSub = SubscriptionService.instance.messages.listen(_showSnackBar);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openManageSubscription() async {
    final uri = Uri.tryParse(premiumManageSubscriptionsUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Entitlement>(
      valueListenable: EntitlementService.instance.listenable,
      builder: (context, _, _) {
        final unlocked = EntitlementService.instance.premiumUnlocked;
        return _buildSettingsSection(
          title: 'Premium',
          children: unlocked ? _activeChildren() : _inactiveChildren(),
        );
      },
    );
  }

  List<Widget> _inactiveChildren() {
    return [
      _SettingsTile(
        icon: Icons.workspace_premium_outlined,
        title: 'Upgrade to Premium',
        subtitle: 'Unlock offline routes and details',
        onTap: () => showPaywallSheet(context),
      ),
      _SettingsTile(
        icon: Icons.restore,
        title: 'Restore purchases',
        subtitle: 'Already subscribed? Restore on this device',
        onTap: () => SubscriptionService.instance.restore(),
      ),
    ];
  }

  List<Widget> _activeChildren() {
    return [
      _buildStatusTile(),
      _SettingsTile(
        icon: Icons.manage_accounts_outlined,
        title: 'Manage subscription',
        subtitle: 'Change or cancel in Google Play',
        onTap: _openManageSubscription,
      ),
      _SettingsTile(
        icon: Icons.restore,
        title: 'Restore purchases',
        onTap: () => SubscriptionService.instance.restore(),
      ),
    ];
  }

  Widget _buildStatusTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.verified, color: MapColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Premium active',
                  style: TextStyle(
                    color: MapColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Offline routes are unlocked',
                  style: TextStyle(
                    color: MapColors.text.withValues(alpha: 0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
