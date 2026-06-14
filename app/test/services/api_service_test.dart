import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:repiq/services/api_service.dart';

ApiService _serviceWith(http.Response Function(http.Request) handler) =>
    ApiService(client: MockClient((req) async => handler(req)));

ApiService _serviceWithStreamed(
  http.StreamedResponse Function(http.BaseRequest) handler,
) => ApiService(client: MockClient.streaming((req, __) async => handler(req)));

final _csvBytes = Uint8List.fromList(
  'Date,Exercise\n2026-01-01,Squat'.codeUnits,
);

void main() {
  group('ApiService.getRecommendation', () {
    test('200 returns a parsed Recommendation', () async {
      final api = _serviceWith(
        (_) => http.Response(
          jsonEncode({
            'target_reps': 8,
            'target_weight': 135.0,
            'status': 'PROGRESSION: Weight Increased',
            'predicted_1rm': 161.0,
            'required_1rm': 155.0,
            'notes_insight': 'Good momentum!',
          }),
          200,
        ),
      );

      final rec = await api.getRecommendation(
        'Bench Press',
        'Chest',
        authToken: 'token',
      );
      expect(rec, isNotNull);
      expect(rec!.targetWeight, 135.0);
      expect(rec.targetReps, 8);
      expect(rec.status, contains('PROGRESSION'));
      expect(rec.notesInsight, 'Good momentum!');
    });

    test('404 returns null', () async {
      final api = _serviceWith((_) => http.Response('not found', 404));
      expect(
        await api.getRecommendation('Bench Press', 'Chest', authToken: 't'),
        isNull,
      );
    });

    test('403 returns null', () async {
      final api = _serviceWith((_) => http.Response('forbidden', 403));
      expect(
        await api.getRecommendation('Bench Press', 'Chest', authToken: 't'),
        isNull,
      );
    });

    test('500 throws an exception', () async {
      final api = _serviceWith((_) => http.Response('error', 500));
      expect(
        () => api.getRecommendation('Bench Press', 'Chest', authToken: 't'),
        throwsException,
      );
    });

    test('sends auth header when token provided', () async {
      String? capturedAuth;
      final api = ApiService(
        client: MockClient((req) async {
          capturedAuth = req.headers['Authorization'];
          return http.Response(
            jsonEncode({
              'target_reps': 8,
              'target_weight': 100.0,
              'status': 'X',
              'predicted_1rm': 110.0,
              'required_1rm': 105.0,
              'notes_insight': '',
            }),
            200,
          );
        }),
      );

      await api.getRecommendation('Squat', 'Legs', authToken: 'my_token');
      expect(capturedAuth, 'Bearer my_token');
    });

    test('sends no auth header when token is null', () async {
      String? capturedAuth;
      final api = ApiService(
        client: MockClient((req) async {
          capturedAuth = req.headers['Authorization'];
          return http.Response('not found', 404);
        }),
      );

      await api.getRecommendation('Squat', 'Legs');
      expect(capturedAuth, isNull);
    });

    test('sends mode in request body', () async {
      String? capturedBody;
      final api = ApiService(
        client: MockClient((req) async {
          capturedBody = req.body;
          return http.Response('not found', 404);
        }),
      );

      await api.getRecommendation('Squat', 'Legs', mode: 'strength');
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['mode'], 'strength');
    });
  });

  group('ApiService.trainFromCsvBytes', () {
    test('200 completes without throwing', () async {
      final api = _serviceWithStreamed(
        (_) => http.StreamedResponse(
          Stream.value(utf8.encode('{"message":"ok"}')),
          200,
        ),
      );
      await expectLater(
        api.trainFromCsvBytes(_csvBytes, authToken: 'token'),
        completes,
      );
    });

    test('401 throws with sign-in message', () async {
      final api = _serviceWithStreamed(
        (_) => http.StreamedResponse(
          Stream.value(utf8.encode('unauthorized')),
          401,
        ),
      );
      expect(
        () => api.trainFromCsvBytes(_csvBytes, authToken: 'token'),
        throwsA(predicate<Exception>((e) => e.toString().contains('sign in'))),
      );
    });

    test('403 throws with premium message', () async {
      final api = _serviceWithStreamed(
        (_) =>
            http.StreamedResponse(Stream.value(utf8.encode('forbidden')), 403),
      );
      expect(
        () => api.trainFromCsvBytes(_csvBytes, authToken: 'token'),
        throwsA(predicate<Exception>((e) => e.toString().contains('Premium'))),
      );
    });

    test('409 throws with in-progress message', () async {
      final api = _serviceWithStreamed(
        (_) =>
            http.StreamedResponse(Stream.value(utf8.encode('conflict')), 409),
      );
      expect(
        () => api.trainFromCsvBytes(_csvBytes, authToken: 'token'),
        throwsA(
          predicate<Exception>((e) => e.toString().contains('in progress')),
        ),
      );
    });

    test('413 throws with too-large message', () async {
      final api = _serviceWithStreamed(
        (_) =>
            http.StreamedResponse(Stream.value(utf8.encode('too large')), 413),
      );
      expect(
        () => api.trainFromCsvBytes(_csvBytes, authToken: 'token'),
        throwsA(
          predicate<Exception>((e) => e.toString().contains('too large')),
        ),
      );
    });

    test('500 throws with body in message', () async {
      final api = _serviceWithStreamed(
        (_) => http.StreamedResponse(
          Stream.value(utf8.encode('server exploded')),
          500,
        ),
      );
      expect(
        () => api.trainFromCsvBytes(_csvBytes, authToken: 'token'),
        throwsA(
          predicate<Exception>((e) => e.toString().contains('server exploded')),
        ),
      );
    });
  });

  group('ApiService.deleteUserData', () {
    test('200 completes without throwing', () async {
      final api = _serviceWith((_) => http.Response('{"message":"ok"}', 200));
      await expectLater(api.deleteUserData(authToken: 'token'), completes);
    });

    test('non-200 throws with status code', () async {
      final api = _serviceWith((_) => http.Response('error', 500));
      expect(
        () => api.deleteUserData(authToken: 'token'),
        throwsA(predicate<Exception>((e) => e.toString().contains('500'))),
      );
    });

    test('sends auth header', () async {
      String? capturedAuth;
      final api = ApiService(
        client: MockClient((req) async {
          capturedAuth = req.headers['Authorization'];
          return http.Response('{"message":"ok"}', 200);
        }),
      );
      await api.deleteUserData(authToken: 'my_token');
      expect(capturedAuth, 'Bearer my_token');
    });
  });
}
