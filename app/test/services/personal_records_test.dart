import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/personal_records.dart';

WorkoutSet _set(
  int day,
  double weight,
  int reps, {
  String exercise = 'Bench Press',
  String comment = '',
}) => WorkoutSet(
  date: DateTime(2025, 1, day),
  exercise: exercise,
  category: 'Chest',
  weight: weight,
  reps: reps,
  comment: comment,
);

void main() {
  test('first set and every later improvement are PRs', () {
    final prs = personalRecordDates([
      _set(1, 100, 10),
      _set(2, 100, 8),
      _set(3, 105, 5),
      _set(4, 100, 12),
    ]);
    expect(prs, {
      DateTime(2025, 1, 1),
      DateTime(2025, 1, 3),
      DateTime(2025, 1, 4),
    });
  });

  test('ties are not PRs', () {
    final prs = personalRecordDates([_set(1, 100, 10), _set(2, 100, 10)]);
    expect(prs, {DateTime(2025, 1, 1)});
  });

  test('warm-ups, unweighted and assisted sets never count', () {
    final prs = personalRecordDates([
      _set(1, 200, 5, comment: 'warm-up'),
      _set(2, 0, 20),
      _set(3, 50, 8, exercise: 'Assisted Pull Up'),
    ]);
    expect(prs, isEmpty);
  });

  test('records are tracked per exercise', () {
    final prs = personalRecordDates([
      _set(1, 200, 5),
      _set(2, 50, 5, exercise: 'Curl'),
    ]);
    expect(prs, {DateTime(2025, 1, 1), DateTime(2025, 1, 2)});
  });
}
