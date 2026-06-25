import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/config/billing_config.dart';
import '../models/entitlement.dart';

/// Timeout for subscription verification requests.
const Duration _verifyApiTimeout = Duration(seconds: 15);

/// The single seam between "Play says it's purchased" and "the app's canonical
/// entitlement". Swapping client-only trust for real backend validation is a
/// one-flag change (`kUseServerVerification`) — callers never change.
///
/// Mirrors the stateless `lib/data/` client style (see `feedback_client.dart`).
class SubscriptionVerificationClient {
  const SubscriptionVerificationClient();

  /// Resolves a Play purchase into a canonical [Entitlement].
  ///
  /// - Client-only phase (`kUseServerVerification == false`): trusts the local
  ///   Play purchase and returns an active entitlement stamped now. The real
  ///   `expiryTime` is unknown without the backend, so it's left null and the
  ///   offline TTL bounds how long access persists.
  /// - Server phase (`kUseServerVerification == true`): POSTs the token to the
  ///   backend, which validates with the Play Developer API and returns the
  ///   authoritative entitlement (status + expiry + willRenew).
  Future<Entitlement> verify({
    required String productId,
    required String purchaseToken,
    http.Client? client,
  }) async {
    if (!kUseServerVerification) {
      return Entitlement(
        status: PremiumStatus.active,
        willRenew: true,
        lastVerifiedAt: DateTime.now(),
      );
    }

    final uri = Uri.parse(subscriptionVerifyApiUrl);
    final body = jsonEncode(<String, String>{
      'productId': productId,
      'purchaseToken': purchaseToken,
    });

    try {
      final httpClient = client ?? http.Client();
      try {
        final response = await httpClient
            .post(
              uri,
              headers: const <String, String>{
                'Content-Type': 'application/json',
              },
              body: body,
            )
            .timeout(_verifyApiTimeout);

        if (response.statusCode != 200) {
          throw SubscriptionVerificationException(
            _extractApiMessage(response.body) ??
                'Verification API returned ${response.statusCode}',
          );
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw SubscriptionVerificationException(
            'Unexpected verification response.',
          );
        }
        return Entitlement.fromJson(decoded).copyWith(
          lastVerifiedAt: DateTime.now(),
        );
      } finally {
        if (client == null) httpClient.close();
      }
    } on SubscriptionVerificationException {
      rethrow;
    } on TimeoutException {
      throw SubscriptionVerificationException(
        'Verification timed out. Please try again.',
      );
    } catch (_) {
      throw SubscriptionVerificationException(
        'Unable to verify your subscription right now.',
      );
    }
  }

  String? _extractApiMessage(String responseBody) {
    try {
      final json = jsonDecode(responseBody);
      if (json is! Map<String, dynamic>) return null;
      final message = json['message'] ?? json['error'] ?? json['detail'];
      return message?.toString();
    } catch (_) {
      return null;
    }
  }
}

/// Thrown when subscription verification fails.
class SubscriptionVerificationException implements Exception {
  SubscriptionVerificationException(this.message);

  final String message;

  @override
  String toString() => 'SubscriptionVerificationException: $message';
}
