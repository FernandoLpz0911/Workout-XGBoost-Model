import 'package:flutter/foundation.dart';
import 'package:repiq/models/body_measurement.dart';
import 'package:repiq/services/local_storage_service.dart';

/// Loads and mutates body-tracker readings (bodyweight, body fat %).
class BodyTrackerViewModel extends ChangeNotifier {
  final _storage = LocalStorageService();

  List<BodyMeasurement> measurements = [];
  bool isLoading = true;

  BodyTrackerViewModel() {
    _load();
  }

  Future<void> _load() async {
    measurements = await _storage.loadBodyMeasurements();
    isLoading = false;
    notifyListeners();
  }

  List<BodyMeasurement> forType(BodyMeasurementType type) =>
      measurements.where((m) => m.type == type).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  Future<void> addMeasurement(BodyMeasurementType type, double value) async {
    final id = await _storage.addBodyMeasurement(
      BodyMeasurement(date: DateTime.now(), type: type, value: value),
    );
    measurements = [
      ...measurements,
      BodyMeasurement(id: id, date: DateTime.now(), type: type, value: value),
    ];
    notifyListeners();
  }

  Future<void> deleteMeasurement(BodyMeasurement m) async {
    if (m.id == null) return;
    await _storage.deleteBodyMeasurement(m.id!);
    measurements = measurements.where((x) => x.id != m.id).toList();
    notifyListeners();
  }
}
