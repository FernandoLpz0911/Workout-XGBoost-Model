import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/body_measurement.dart';

void main() {
  group('BodyMeasurement — copyWith', () {
    test('assigns a new id while preserving other fields', () {
      final date = DateTime(2026, 3, 1);
      final original = BodyMeasurement(
        date: date,
        type: BodyMeasurementType.weight,
        value: 180.0,
      );
      final withId = original.copyWith(id: 7);
      expect(withId.id, 7);
      expect(withId.date, date);
      expect(withId.type, BodyMeasurementType.weight);
      expect(withId.value, 180.0);
    });

    test('keeps the existing id when none is passed', () {
      final original = BodyMeasurement(
        id: 3,
        date: DateTime(2026, 3, 1),
        type: BodyMeasurementType.bodyFat,
        value: 18.5,
      );
      expect(original.copyWith().id, 3);
    });
  });
}
