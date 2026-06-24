/// Premium entitlement state for the offline-routes subscription.
///
/// This is the single value the rest of the app reasons about. The billing
/// layer produces it; the Routes/offline feature consumes it. See
/// `secrets/docs/google_play/subscription_architecture.md`.
enum PremiumStatus { none, active, inGracePeriod, onHold, expired }

/// Immutable snapshot of the user's premium entitlement.
class Entitlement {
  const Entitlement({
    required this.status,
    this.expiryTime,
    this.willRenew = false,
    this.lastVerifiedAt,
  });

  /// Canonical subscription status (from the backend when server verification
  /// is enabled, otherwise inferred from Play's local purchase state).
  final PremiumStatus status;

  /// When the current paid period ends, if known. `null` in the client-only
  /// phase where the real expiry isn't available without backend validation.
  final DateTime? expiryTime;

  /// Whether the subscription is set to auto-renew.
  final bool willRenew;

  /// When verification last succeeded. Drives the offline trust window (TTL).
  final DateTime? lastVerifiedAt;

  /// Whether this entitlement, on its own, grants offline-routes access.
  /// TTL/expiry gating is applied by `EntitlementService`, not here.
  bool get hasOfflineRoutes =>
      status == PremiumStatus.active || status == PremiumStatus.inGracePeriod;

  /// The "no entitlement" baseline.
  static const Entitlement none = Entitlement(status: PremiumStatus.none);

  Entitlement copyWith({
    PremiumStatus? status,
    DateTime? expiryTime,
    bool? willRenew,
    DateTime? lastVerifiedAt,
  }) {
    return Entitlement(
      status: status ?? this.status,
      expiryTime: expiryTime ?? this.expiryTime,
      willRenew: willRenew ?? this.willRenew,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status.name,
        'expiryTime': expiryTime?.toIso8601String(),
        'willRenew': willRenew,
        'lastVerifiedAt': lastVerifiedAt?.toIso8601String(),
      };

  factory Entitlement.fromJson(Map<String, dynamic> json) {
    return Entitlement(
      status: PremiumStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => PremiumStatus.none,
      ),
      expiryTime: _parseDate(json['expiryTime']),
      willRenew: json['willRenew'] as bool? ?? false,
      lastVerifiedAt: _parseDate(json['lastVerifiedAt']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  @override
  String toString() =>
      'Entitlement(status: $status, expiryTime: $expiryTime, '
      'willRenew: $willRenew, lastVerifiedAt: $lastVerifiedAt)';
}
