/// Which body metric a [BodyMeasurement] records.
enum BodyMeasurementType { weight, bodyFat }

/// One logged body-tracker reading — bodyweight (lbs) or body fat (%).
class BodyMeasurement {
  /// SQLite row id. Null until the reading has been persisted.
  final int? id;
  final DateTime date;
  final BodyMeasurementType type;
  final double value;

  const BodyMeasurement({
    this.id,
    required this.date,
    required this.type,
    required this.value,
  });

  BodyMeasurement copyWith({int? id}) =>
      BodyMeasurement(id: id ?? this.id, date: date, type: type, value: value);
}
