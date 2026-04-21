import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/config/api_config.dart';
import '../models/navigate_suggestion.dart';

const Duration _navigateApiTimeout = Duration(seconds: 15);

/// Calls POST /api/public/navigate and returns parsed route suggestions.
Future<List<NavigateSuggestion>> fetchNavigationSuggestions({
  required LatLng start,
  required LatLng end,
  http.Client? client,
}) async {
  final uri = Uri.parse(navigateApiUrl);
  final body = jsonEncode(<String, dynamic>{
    'start': <double>[start.latitude, start.longitude],
    'end': <double>[end.latitude, end.longitude],
  });

  try {
    final response = client != null
        ? await client
              .post(
                uri,
                headers: const <String, String>{
                  'Content-Type': 'application/json',
                },
                body: body,
              )
              .timeout(_navigateApiTimeout)
        : await http
              .post(
                uri,
                headers: const <String, String>{
                  'Content-Type': 'application/json',
                },
                body: body,
              )
              .timeout(_navigateApiTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final apiMessage = _extractApiMessage(response.body);
      throw NavigateRequestException(
        apiMessage ?? 'Navigate API returned ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const NavigateRequestException(
        'Navigate API returned invalid JSON payload.',
      );
    }

    final parsed = NavigateSuggestionsResponse.fromJson(decoded);
    if (!parsed.ok) {
      final apiMessage = _extractApiMessage(response.body);
      throw NavigateRequestException(
        apiMessage ?? 'Navigate API did not return a successful response.',
      );
    }

    return parsed.suggestions;
  } on NavigateRequestException {
    rethrow;
  } on TimeoutException {
    throw const NavigateRequestException(
      'Navigation request timed out. Please try again.',
    );
  } catch (_) {
    throw const NavigateRequestException(
      'Unable to fetch navigation suggestions right now. Please try again.',
    );
  }
}

String? _extractApiMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    final topLevel =
        decoded['message'] ?? decoded['error'] ?? decoded['detail'];
    if (topLevel != null) return topLevel.toString();

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return null;

    final nested = data['message'] ?? data['error'] ?? data['detail'];
    return nested?.toString();
  } catch (_) {
    return null;
  }
}

class NavigateRequestException implements Exception {
  const NavigateRequestException(this.message);

  final String message;

  @override
  String toString() => 'NavigateRequestException: $message';
}
