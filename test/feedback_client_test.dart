import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:jippy_mobile/core/config/api_config.dart';
import 'package:jippy_mobile/data/feedback_client.dart';

void main() {
  group('FeedbackClient', () {
    test('submitFeedback posts required payload and succeeds on 201', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), feedbackApiUrl);
        expect(request.headers['Content-Type'], 'application/json');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], 'user@example.com');
        expect(body['type'], 'Application Bug');
        expect(body['details'], 'App crashes when opening map.');

        return http.Response('', 201);
      });

      await expectLater(
        submitFeedback(
          email: 'user@example.com',
          type: 'Application Bug',
          details: 'App crashes when opening map.',
          client: client,
        ),
        completes,
      );
    });

    test('submitFeedback throws on non-201 responses', () async {
      final client = MockClient(
        (_) async => http.Response('{"message":"Invalid payload"}', 400),
      );

      await expectLater(
        submitFeedback(
          email: 'user@example.com',
          type: 'Road Closure',
          details: 'Road is blocked near downtown.',
          client: client,
        ),
        throwsA(
          isA<FeedbackSubmissionException>().having(
            (e) => e.message,
            'message',
            'Invalid payload',
          ),
        ),
      );
    });

    test('submitFeedback throws generic failure on network errors', () async {
      final client = MockClient((_) async => throw Exception('socket error'));

      await expectLater(
        submitFeedback(
          email: 'user@example.com',
          type: 'Road Closure',
          details: 'Road is blocked near downtown.',
          client: client,
        ),
        throwsA(isA<FeedbackSubmissionException>()),
      );
    });

    test('submitFeedback throws when required fields are empty', () async {
      await expectLater(
        submitFeedback(email: '', type: 'Road Closure', details: 'x'),
        throwsArgumentError,
      );
      await expectLater(
        submitFeedback(email: 'user@example.com', type: '', details: 'x'),
        throwsArgumentError,
      );
      await expectLater(
        submitFeedback(
          email: 'user@example.com',
          type: 'Road Closure',
          details: '',
        ),
        throwsArgumentError,
      );
    });
  });
}
