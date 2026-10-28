import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/repeat_workout.dart';

WorkoutSet _set(DateTime date, String exercise, {String category = 'Chest'}) =>
    WorkoutSet(
      date: date,
      exercise: exercise,
      category: category,
      weight: 100,
      reps: 10,
    );

void main() {
  final today = DateTime(2025, 3, 10, 9);

  test('returns the most recent earlier day in performed order', () {
    final history = [
      _set(DateTime(2025, 3, 1, 10), 'Squat', category: 'Legs'),
      _set(DateTime(2025, 3, 5, 10, 5), 'Curl', category: 'Arms'),
      _set(DateTime(2025, 3, 5, 10, 0), 'Bench Press'),
      _set(DateTime(2025, 3, 5, 10, 1), 'Bench Press'),
    ];
    expect(lastWorkoutExercises(history, today), [
      ('Chest', 'Bench Press'),
      ('Arms', 'Curl'),
    ]);
  });

  test('ignores sets already logged today', () {
    final history = [
      _set(DateTime(2025, 3, 5, 10), 'Bench Press'),
      _set(DateTime(2025, 3, 10, 8), 'Squat', category: 'Legs'),
    ];
    expect(lastWorkoutExercises(history, today), [('Chest', 'Bench Press')]);
  });

  test('empty history gives nothing', () {
    expect(lastWorkoutExercises([], today), isEmpty);
  });
}
