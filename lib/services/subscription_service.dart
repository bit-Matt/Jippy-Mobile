import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/config/billing_config.dart';
import '../data/subscription_verification_client.dart';
import 'entitlement_service.dart';

/// Singleton wrapper around Google Play Billing (`in_app_purchase`).
///
/// Responsibilities: initialise the store connection, load the premium
/// subscription product, launch purchases, restore past purchases, and route
/// every purchase update through verification into [EntitlementService].
/// See `subscription_architecture.md` §3 and §6.
class SubscriptionService {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  final SubscriptionVerificationClient _verifier =
      const SubscriptionVerificationClient();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _initialized = false;

  /// Whether the store is reachable on this device/build.
  final ValueNotifier<bool> isStoreAvailable = ValueNotifier<bool>(false);

  /// Loaded product details for the premium subscription (empty until loaded).
  final ValueNotifier<List<ProductDetails>> products =
      ValueNotifier<List<ProductDetails>>(const <ProductDetails>[]);

  /// True while a purchase/restore is in flight (drives button spinners).
  final ValueNotifier<bool> purchasePending = ValueNotifier<bool>(false);

  /// Transient, user-facing messages (snackbar text). Broadcast so multiple
  /// surfaces (paywall + settings) can listen.
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  /// The premium product details, if loaded.
  ProductDetails? get premiumProduct {
    for (final p in products.value) {
      if (p.id == premiumOfflineProductId) return p;
    }
    return null;
  }

  /// Connects to the store, starts listening for purchase updates, loads the
  /// product, and silently restores existing purchases. Safe to call once.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (Object error) {
        _emit('Store connection error. Please try again later.');
        purchasePending.value = false;
      },
    );

    bool available = false;
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      available = false;
    }
    isStoreAvailable.value = available;
    if (!available) return;

    await _loadProducts();

    // Silently recover entitlement after reinstall / new device. Results
    // arrive on the purchase stream and are handled like any restore.
    try {
      await _iap.restorePurchases();
    } catch (_) {
      // Non-fatal; the user can restore manually from Settings.
    }
  }

  Future<void> _loadProducts() async {
    try {
      final response =
          await _iap.queryProductDetails(<String>{premiumOfflineProductId});
      if (response.error != null) {
        _emit('Could not load subscription details.');
        return;
      }
      products.value = response.productDetails;
      if (response.notFoundIDs.contains(premiumOfflineProductId)) {
        // Product not configured/active in the Play Console for this account.
        _emit('Subscription is not available yet.');
      }
    } catch (_) {
      _emit('Could not load subscription details.');
    }
  }

  /// Launches the purchase flow for the premium subscription.
  Future<void> buyPremium() async {
    final product = premiumProduct;
    if (product == null) {
      _emit('Subscription is not available right now.');
      return;
    }
    purchasePending.value = true;
    try {
      final param = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (_) {
      purchasePending.value = false;
      _emit('Could not start the purchase. Please try again.');
    }
  }

  /// Restores previously purchased subscriptions for the signed-in Play account.
  Future<void> restore() async {
    purchasePending.value = true;
    try {
      await _iap.restorePurchases();
      _emit('Restoring your purchases…');
    } catch (_) {
      _emit('Could not restore purchases. Please try again.');
    } finally {
      // Actual results (if any) arrive via the purchase stream.
      purchasePending.value = false;
    }
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          purchasePending.value = true;
          break;
        case PurchaseStatus.error:
          purchasePending.value = false;
          _emit(purchase.error?.message ?? 'Purchase failed. Please try again.');
          break;
        case PurchaseStatus.canceled:
          purchasePending.value = false;
          _emit('Purchase canceled.');
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliver(purchase);
          break;
      }

      // Always acknowledge/finish, or Google auto-refunds within ~3 days.
      if (purchase.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(purchase);
        } catch (_) {
          // Will be retried on the next purchase stream emission.
        }
      }
    }
  }

  Future<void> _deliver(PurchaseDetails purchase) async {
    try {
      final entitlement = await _verifier.verify(
        productId: purchase.productID,
        purchaseToken: purchase.verificationData.serverVerificationData,
      );
      await EntitlementService.instance.update(entitlement);
      if (purchase.status == PurchaseStatus.purchased) {
        _emit('Premium unlocked. Enjoy offline routes!');
      }
    } catch (e) {
      _emit(
        e is SubscriptionVerificationException
            ? e.message
            : 'Could not confirm your subscription.',
      );
    } finally {
      purchasePending.value = false;
    }
  }

  void _emit(String message) {
    if (!_messages.isClosed) _messages.add(message);
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    await _messages.close();
  }
}
