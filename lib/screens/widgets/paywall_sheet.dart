import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/billing_config.dart';
import '../../core/theme/map_colors.dart';
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
    backgroundColor: MapColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
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
              _buildSheetHandle(),
              const SizedBox(height: 18),
              _buildHeader(),
              const SizedBox(height: 8),
              _buildSubtitle(),
              const SizedBox(height: 18),
              _buildFeature('Offline access to routes & stops'),
              _buildFeature('Route details available without a connection'),
              _buildFeature(
                kPseudoBillingEnabled
                    ? 'Sandbox mode — no real charge'
                    : 'Cancel anytime from Google Play',
              ),
              const SizedBox(height: 20),
              if (kPseudoBillingEnabled) ...[
                _buildSandboxBanner(),
                const SizedBox(height: 12),
                _buildSandboxPriceCard(),
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
                        child: Text(
                          'Reset sandbox subscription',
                          style: TextStyle(
                            color: MapColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Internal testing only. This simulates a Google Play '
                  'subscription checkout without charging your account. '
                  'Use Reset to test the locked state again.',
                  style: TextStyle(
                    color: MapColors.text.withValues(alpha: 0.55),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ] else ...[
                _buildPriceCard(),
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
                        child: Text(
                          'Restore purchases',
                          style: TextStyle(
                            color: MapColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                  style: TextStyle(
                    color: MapColors.text.withValues(alpha: 0.55),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              _buildLegalLinks(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: MapColors.text.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.workspace_premium_outlined,
            color: MapColors.primary, size: 28),
        const SizedBox(width: 10),
        const Text(
          'Jippy Premium',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitle() {
    return Text(
      'Save routes and their details for offline access — '
      'navigate even without a connection.',
      style: TextStyle(
        color: MapColors.text.withValues(alpha: 0.7),
        fontSize: 14,
        height: 1.35,
      ),
    );
  }

  Widget _buildSandboxBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MapColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MapColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: MapColors.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sandbox checkout — mimics Google Play for internal testing. '
              'No payment is collected.',
              style: TextStyle(
                color: MapColors.text.withValues(alpha: 0.85),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSandboxPriceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MapColors.primary.withValues(alpha: 0.3)),
        color: MapColors.primary.withValues(alpha: 0.05),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Premium (Offline Routes)',
                  style: TextStyle(
                    color: MapColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Billed $premiumOfflineBasePlanId · sandbox',
                  style: TextStyle(
                    color: MapColors.text.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            sandboxPremiumPriceLabel,
            style: TextStyle(
              color: MapColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSandboxSubscribeButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: SubscriptionService.instance.purchasePending,
      builder: (context, pending, _) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: pending
                ? null
                : () => SubscriptionService.instance.grantSandboxPremium(),
            icon: pending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_open_outlined),
            label: Text(
              pending ? 'Processing…' : 'Confirm sandbox subscription',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: MapColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeature(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: MapColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: MapColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard() {
    return ValueListenableBuilder<List<ProductDetails>>(
      valueListenable: SubscriptionService.instance.products,
      builder: (context, _, _) {
        final product = SubscriptionService.instance.premiumProduct;
        final priceText = product?.price ?? '—';
        final title = product?.title.isNotEmpty == true
            ? product!.title
            : 'Premium (Offline Routes)';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MapColors.primary.withValues(alpha: 0.3)),
            color: MapColors.primary.withValues(alpha: 0.05),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stripAppName(title),
                      style: const TextStyle(
                        color: MapColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Billed $premiumOfflineBasePlanId',
                      style: TextStyle(
                        color: MapColors.text.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                priceText,
                style: TextStyle(
                  color: MapColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_open_outlined),
                label: Text(pending ? 'Processing…' : 'Subscribe'),
                style: FilledButton.styleFrom(
                  backgroundColor: MapColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLegalLinks() {
    final links = <Widget>[];
    if (premiumTermsUrl != null) {
      links.add(_linkButton('Terms', premiumTermsUrl!));
    }
    if (premiumPrivacyUrl != null) {
      links.add(_linkButton('Privacy Policy', premiumPrivacyUrl!));
    }
    if (links.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, children: links),
    );
  }

  Widget _linkButton(String label, String url) {
    return TextButton(
      onPressed: () => _openUrl(url),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: MapColors.text.withValues(alpha: 0.6),
          fontSize: 12,
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
