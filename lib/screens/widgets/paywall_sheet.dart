import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/billing_config.dart';
import '../../services/entitlement_service.dart';
import '../../services/subscription_service.dart';

/// Shows the Premium upgrade paywall as a modal bottom sheet.
///
/// Play policy requires the price, billing period, and auto-renewal terms to be
/// clearly shown (see `subscription_architecture.md` §9).
Future<void> showPaywallSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _PaywallSheet(),
  );
}

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet();

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  StreamSubscription<String>? _messageSub;

  @override
  void initState() {
    super.initState();
    _messageSub = SubscriptionService.instance.messages.listen(_showSnackBar);
    EntitlementService.instance.listenable.addListener(_onEntitlementChanged);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    EntitlementService.instance.listenable.removeListener(_onEntitlementChanged);
    super.dispose();
  }

  void _onEntitlementChanged() {
    if (mounted && EntitlementService.instance.premiumUnlocked) {
      Navigator.of(context).maybePop();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Jippy Premium',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Save routes and their details for offline access — '
                'navigate even without a connection.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              _buildFeature(context, 'Offline access to routes & stops'),
              _buildFeature(
                context,
                'Route details available without a connection',
              ),
              _buildFeature(
                context,
                kPseudoBillingEnabled
                    ? 'Sandbox mode — no real charge'
                    : 'Cancel anytime from Google Play',
              ),
              const SizedBox(height: 20),
              if (kPseudoBillingEnabled) ...[
                _buildSandboxBanner(context),
                const SizedBox(height: 12),
                _buildSandboxPriceCard(context),
                const SizedBox(height: 16),
                _buildSandboxSubscribeButton(),
                const SizedBox(height: 8),
                Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable:
                        SubscriptionService.instance.purchasePending,
                    builder: (context, pending, _) {
                      return TextButton(
                        onPressed: pending
                            ? null
                            : () => SubscriptionService.instance
                                .resetSandboxPremium(),
                        child: const Text('Reset sandbox subscription'),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Internal testing only. This simulates a Google Play '
                  'subscription checkout without charging your account. '
                  'Use Reset to test the locked state again.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                _buildPriceCard(context),
                const SizedBox(height: 16),
                _buildSubscribeButton(),
                const SizedBox(height: 8),
                Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable:
                        SubscriptionService.instance.purchasePending,
                    builder: (context, pending, _) {
                      return TextButton(
                        onPressed: pending
                            ? null
                            : () => SubscriptionService.instance.restore(),
                        child: const Text('Restore purchases'),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This is an auto-renewing subscription. Payment is charged to '
                  'your Google Play account and renews automatically until '
                  'canceled at least 24 hours before the end of the current '
                  'period. Manage or cancel anytime in Google Play.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              _buildLegalLinks(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSandboxBanner(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.science_outlined,
              color: colorScheme.onTertiaryContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sandbox checkout — mimics Google Play for internal testing. '
                'No payment is collected.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSandboxPriceCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Premium (Offline Routes)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Billed $premiumOfflineBasePlanId · sandbox',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              sandboxPremiumPriceLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSandboxSubscribeButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: SubscriptionService.instance.purchasePending,
      builder: (context, pending, _) {
        final colorScheme = Theme.of(context).colorScheme;
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: pending
                ? null
                : () => SubscriptionService.instance.grantSandboxPremium(),
            icon: pending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.lock_open_outlined),
            label: Text(
              pending ? 'Processing…' : 'Confirm sandbox subscription',
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeature(BuildContext context, String text) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ValueListenableBuilder<List<ProductDetails>>(
      valueListenable: SubscriptionService.instance.products,
      builder: (context, _, _) {
        final product = SubscriptionService.instance.premiumProduct;
        final priceText = product?.price ?? '—';
        final title = product?.title.isNotEmpty == true
            ? product!.title
            : 'Premium (Offline Routes)';
        return Card(
          color: colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stripAppName(title),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Billed $premiumOfflineBasePlanId',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  priceText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubscribeButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: SubscriptionService.instance.purchasePending,
      builder: (context, pending, _) {
        return ValueListenableBuilder<List<ProductDetails>>(
          valueListenable: SubscriptionService.instance.products,
          builder: (context, _, _) {
            final colorScheme = Theme.of(context).colorScheme;
            final hasProduct =
                SubscriptionService.instance.premiumProduct != null;
            final disabled = pending || !hasProduct;
            return SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: disabled
                    ? null
                    : () => SubscriptionService.instance.buyPremium(),
                icon: pending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.lock_open_outlined),
                label: Text(pending ? 'Processing…' : 'Subscribe'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLegalLinks(BuildContext context) {
    final links = <Widget>[];
    if (premiumTermsUrl != null) {
      links.add(_linkButton(context, 'Terms', premiumTermsUrl!));
    }
    if (premiumPrivacyUrl != null) {
      links.add(_linkButton(context, 'Privacy Policy', premiumPrivacyUrl!));
    }
    if (links.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, children: links),
    );
  }

  Widget _linkButton(BuildContext context, String label, String url) {
    return TextButton(
      onPressed: () => _openUrl(url),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              decoration: TextDecoration.underline,
            ),
      ),
    );
  }

  /// Play often returns titles like "Premium (Jippy)" — trim the trailing
  /// app-name parenthetical for a cleaner label.
  String _stripAppName(String title) {
    final idx = title.indexOf(' (');
    return idx > 0 ? title.substring(0, idx) : title;
  }
}
