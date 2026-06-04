import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// HTTP client for the cloud FastAPI backend deployed on Google Cloud Run.
///
/// All endpoints that rely on the XGBoost model require this service.
/// The on-device [LocalRecommendationEngine] works independently without any
/// network access.
class ApiService {
  static const String baseUrl =
      'https://workoutmodel-296813230971.us-central1.run.app';

  /// Uploads [csvBytes] to the cloud `/train` endpoint to retrain the XGBoost
  /// model with the latest local data.
  Future<void> trainFromCsvBytes(Uint8List csvBytes) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/train'));
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      csvBytes,
      filename: 'workout_data.csv',
    ));
    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception('Training failed: $body');
    }
  }
}
