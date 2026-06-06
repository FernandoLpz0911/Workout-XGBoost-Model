import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:repiq/models/recommendation_models.dart';

/// HTTP client for the cloud FastAPI backend deployed on Google Cloud Run.
///
/// The on-device [LocalRecommendationEngine] works independently without any
/// network access. This service is used for cloud model retraining (premium)
/// and for fetching XGBoost-powered recommendations (premium, model must exist).
///
/// Pass a custom [client] in tests to intercept HTTP calls without network access.
class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  static const String _base =
      'https://workoutmodel-296813230971.us-central1.run.app';

  final http.Client _client;

  Map<String, String> _authHeader(String? token) =>
      token != null ? {'Authorization': 'Bearer $token'} : {};

  /// Uploads [csvBytes] to `/train` to retrain the user's personal XGBoost
  /// model. Requires a valid premium Firebase ID token.
  Future<void> trainFromCsvBytes(Uint8List csvBytes,
      {String? authToken}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_base/train'));
    if (authToken != null) {
      request.headers['Authorization'] = 'Bearer $authToken';
    }
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      csvBytes,
      filename: 'workout_data.csv',
    ));
    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 30));
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 401) {
        throw Exception('Authentication required. Please sign in.');
      }
      if (streamed.statusCode == 403) {
        throw Exception('Premium subscription required to retrain the model.');
      }
      if (streamed.statusCode == 409) {
        throw Exception(
            'Training already in progress. Wait for it to complete.');
      }
      throw Exception('Training failed: $body');
    }
  }

  /// Fetches a cloud XGBoost recommendation for [exercise] / [category].
  ///
  /// Returns null on 404 (no model trained yet) or 403 (not premium).
  /// Throws on network errors so the caller can surface offline state.
  Future<Recommendation?> getRecommendation(
    String exercise,
    String category, {
    String? authToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_base/recommend'),
          headers: {
            'Content-Type': 'application/json',
            ..._authHeader(authToken),
          },
          body: jsonEncode({'exercise': exercise, 'category': category}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return Recommendation.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    // 403 = not premium, 404 = no model for this user — both are silent fallbacks.
    if (response.statusCode == 403 || response.statusCode == 404) {
      return null;
    }
    throw Exception('Cloud recommend failed (${response.statusCode})');
  }
}
