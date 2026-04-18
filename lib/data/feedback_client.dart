import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';

/// Timeout for feedback submission requests.
const Duration _feedbackApiTimeout = Duration(seconds: 15);

/// Submits feedback to the public feedback endpoint.
///
/// Sends JSON payload with required fields: [email], [type], and [details].
/// A 201 response is considered success. Any other response throws.
Future<void> submitFeedback({
  required String email,
  required String type,
  required String details,
  http.Client? client,
}) async {
  final normalizedEmail = email.trim();
  final normalizedType = type.trim();
  final normalizedDetails = details.trim();

  if (normalizedEmail.isEmpty ||
      normalizedType.isEmpty ||
      normalizedDetails.isEmpty) {
    throw ArgumentError('email, type, and details are required.');
  }

  final uri = Uri.parse(feedbackApiUrl);
  final body = jsonEncode(<String, String>{
    'email': normalizedEmail,
    'type': normalizedType,
    'details': normalizedDetails,
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
              .timeout(_feedbackApiTimeout)
        : await http
              .post(
                uri,
                headers: const <String, String>{
                  'Content-Type': 'application/json',
                },
                body: body,
              )
              .timeout(_feedbackApiTimeout);

    if (response.statusCode != 201) {
      final apiMessage = _extractApiMessage(response.body);
      throw FeedbackSubmissionException(
        apiMessage ?? 'Feedback API returned ${response.statusCode}',
      );
    }
  } on ArgumentError {
    rethrow;
  } on FeedbackSubmissionException {
    rethrow;
  } on TimeoutException {
    throw FeedbackSubmissionException(
      'Feedback request timed out. Please try again.',
    );
  } catch (_) {
    throw FeedbackSubmissionException(
      'Unable to submit feedback right now. Please try again.',
    );
  }
}

String? _extractApiMessage(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return null;

    final message = json['message'] ?? json['error'] ?? json['detail'];
    return message?.toString();
  } catch (_) {
    return null;
  }
}

/// Thrown when feedback submission fails.
class FeedbackSubmissionException implements Exception {
  FeedbackSubmissionException(this.message);

  final String message;

  @override
  String toString() => 'FeedbackSubmissionException: $message';
}
