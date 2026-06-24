import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/billing_config.dart';
import '../models/entitlement.dart';

/// Singleton source of truth for the user's premium status.
///
/// Holds the last canonical [Entitlement] (from verification), persists it
/// locally, and applies the offline trust window (expiry + TTL) so the gated
/// feature works with no network. UI listens via [listenable]; gating code
/// reads [premiumUnlocked]. See `subscription_architecture.md` §4 and §8.
class EntitlementService {
  EntitlementService._();

  static final EntitlementService instance = EntitlementService._();

  static const String _cacheKey = 'entitlement_cache_v1';

  final ValueNotifier<Entitlement> _notifier =
      ValueNotifier<Entitlement>(Entitlement.none);

  /// Listenable canonical entitlement. Rebuild gated UI on changes, then read
  /// [premiumUnlocked] inside the builder so TTL/expiry are applied live.
  ValueListenable<Entitlement> get listenable => _notifier;

  /// The last canonical entitlement (ignores TTL/expiry/debug gating).
  Entitlement get current => _notifier.value;

  bool _initialized = false;

  /// Loads any cached entitlement from disk. Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _notifier.value = Entitlement.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt/unreadable cache → fall back to no entitlement.
      _notifier.value = Entitlement.none;
    }
  }

  /// Whether premium (offline routes) is currently unlocked.
  ///
  /// Grants access only when the cached entitlement grants it AND the paid
  /// period hasn't lapsed AND we've verified recently enough (TTL). The debug
  /// override short-circuits everything in debug builds.
  bool get premiumUnlocked {
    if (kDebugForcePremium && kDebugMode) return true;

    final e = _notifier.value;
    if (!e.hasOfflineRoutes) return false;

    final now = DateTime.now();
    if (e.expiryTime != null && !now.isBefore(e.expiryTime!)) return false;

    final verifiedAt = e.lastVerifiedAt;
    if (verifiedAt == null) return false;
    if (now.difference(verifiedAt) >= entitlementCacheTtl) return false;

    return true;
  }

  /// Replaces the canonical entitlement (after a successful verification) and
  /// persists it. Notifies listeners.
  Future<void> update(Entitlement entitlement) async {
    _notifier.value = entitlement;
    await _persist(entitlement);
  }

  /// Clears any stored entitlement (e.g. subscription fully expired/revoked).
  Future<void> clear() async {
    _notifier.value = Entitlement.none;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {
      // Best-effort; in-memory state is already cleared.
    }
  }

  Future<void> _persist(Entitlement entitlement) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(entitlement.toJson()));
    } catch (_) {
      // Best-effort persistence; in-memory state remains authoritative.
    }
  }
}
