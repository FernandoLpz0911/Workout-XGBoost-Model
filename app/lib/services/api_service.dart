import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl =
      'https://workoutmodel-296813230971.us-central1.run.app';

  /// Uploads [csvBytes] to the cloud /train endpoint to retrain the XGBoost model.
  /// Optional — the local recommendation engine works without this.
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
