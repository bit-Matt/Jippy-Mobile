/// Configuration for the Premium (offline routes) auto-renewing subscription.
///
/// These values must match the product configured in the Google Play Console
/// exactly (see `secrets/docs/google_play/google_play_setup.md` §12 and
/// `subscription_architecture.md`).
library;

import 'package:flutter/foundation.dart';

/// Google Play subscription product ID. Must match the Play Console product
/// exactly. This string is permanent once the product is published.
const String premiumOfflineProductId = 'jippy_premium_offline';

/// Base plan ID configured under the subscription in the Play Console.
/// Used for display/labelling; `in_app_purchase` resolves the offer at buy time.
const String premiumOfflineBasePlanId = 'monthly';

/// How long a verified entitlement is trusted offline before re-verification is
/// required when back online. Tuned against the billing period + grace window.
const Duration entitlementCacheTtl = Duration(days: 3);

/// When `false` (the current phase), entitlement is granted by trusting Play's
/// purchase locally. When `true`, the app POSTs the purchase token to the
/// backend (`subscriptionVerifyApiUrl`) for authoritative validation.
///
/// Keep this `false` until the backend `/subscriptions/verify` endpoint ships.
const bool kUseServerVerification = false;

/// Debug-only override to exercise the gated UI without a real purchase.
/// MUST stay `false` in release builds.
const bool kDebugForcePremium = false;

/// Compile-time opt-in for pseudo billing in release APKs.
///
/// Build with `--dart-define=JIPPY_PSEUDO_BILLING=true` for internal QA APKs.
/// Omit this flag for Play-distributed AAB/release builds.
const bool _kPseudoBillingDartDefine = bool.fromEnvironment(
  'JIPPY_PSEUDO_BILLING',
  defaultValue: false,
);

/// Whether the sandbox pseudo-billing checkout is available.
///
/// Enabled in debug builds and in release APKs built with
/// `JIPPY_PSEUDO_BILLING=true`. Never enabled in a normal production build.
bool get kPseudoBillingEnabled => kDebugMode || _kPseudoBillingDartDefine;

/// Placeholder price shown on the sandbox paywall (no real charge).
const String sandboxPremiumPriceLabel = '₱0.00 (sandbox)';

/// Simulated billing period for sandbox entitlements.
const Duration sandboxSubscriptionPeriod = Duration(days: 30);

/// Deep link to the user's Play subscriptions screen ("Manage subscription").
const String premiumManageSubscriptionsUrl =
    'https://play.google.com/store/account/subscriptions';

/// Public Terms of Service URL shown on the paywall. Leave `null` until hosted;
/// the link is hidden when null.
const String? premiumTermsUrl = null;

/// Public Privacy Policy URL shown on the paywall. Leave `null` until hosted
/// (see `secrets/docs/google_play/privacy_policy.md`); hidden when null.
const String? premiumPrivacyUrl = null;
