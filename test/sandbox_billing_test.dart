import 'package:flutter_test/flutter_test.dart';
import 'package:jippy_mobile/core/config/billing_config.dart';
import 'package:jippy_mobile/models/entitlement.dart';
import 'package:jippy_mobile/services/entitlement_service.dart';
import 'package:jippy_mobile/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EntitlementService.instance.init();
    await EntitlementService.instance.clear();
  });

  group('kPseudoBillingEnabled', () {
    test('is enabled in debug test runs', () {
      expect(kPseudoBillingEnabled, isTrue);
    });
  });

  group('createSandboxEntitlement', () {
    test('returns an active renewable entitlement with expiry', () {
      final now = DateTime(2026, 6, 27, 12);
      final entitlement = createSandboxEntitlement(now: now);

      expect(entitlement.status, PremiumStatus.active);
      expect(entitlement.willRenew, isTrue);
      expect(entitlement.hasOfflineRoutes, isTrue);
      expect(entitlement.lastVerifiedAt, now);
      expect(
        entitlement.expiryTime,
        now.add(sandboxSubscriptionPeriod),
      );
    });
  });

  group('EntitlementService', () {
    test('premiumUnlocked is true after sandbox entitlement update', () async {
      await EntitlementService.instance.update(createSandboxEntitlement());

      expect(EntitlementService.instance.premiumUnlocked, isTrue);
    });

    test('premiumUnlocked is false when verification TTL has lapsed', () async {
      final staleVerifiedAt = DateTime.now().subtract(
        entitlementCacheTtl + const Duration(hours: 1),
      );
      await EntitlementService.instance.update(
        Entitlement(
          status: PremiumStatus.active,
          willRenew: true,
          lastVerifiedAt: staleVerifiedAt,
          expiryTime: DateTime.now().add(const Duration(days: 30)),
        ),
      );

      expect(EntitlementService.instance.premiumUnlocked, isFalse);
    });

    test('premiumUnlocked is false after clear', () async {
      await EntitlementService.instance.update(createSandboxEntitlement());
      await EntitlementService.instance.clear();

      expect(EntitlementService.instance.premiumUnlocked, isFalse);
    });
  });

  group('SubscriptionService sandbox checkout', () {
    test('grantSandboxPremium unlocks premium', () async {
      await SubscriptionService.instance.grantSandboxPremium();

      expect(EntitlementService.instance.premiumUnlocked, isTrue);
      expect(EntitlementService.instance.current.status, PremiumStatus.active);
    });

    test('resetSandboxPremium clears premium access', () async {
      await SubscriptionService.instance.grantSandboxPremium();
      await SubscriptionService.instance.resetSandboxPremium();

      expect(EntitlementService.instance.premiumUnlocked, isFalse);
    });

    test('simulateSandboxCancellation clears premium access', () async {
      await SubscriptionService.instance.grantSandboxPremium();
      await SubscriptionService.instance.simulateSandboxCancellation();

      expect(EntitlementService.instance.premiumUnlocked, isFalse);
    });
  });
}
