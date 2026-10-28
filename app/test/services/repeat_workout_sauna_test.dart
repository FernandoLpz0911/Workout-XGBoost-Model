import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/repeat_workout.dart';

void main() {
  test('timed-only exercises like Sauna are included', () {
    final history = [
      WorkoutSet(
        date: DateTime(2025, 3, 5, 10),
        exercise: 'Bench Press',
        category: 'Chest',
        weight: 100,
        reps: 10,
      ),
      WorkoutSet(
        date: DateTime(2025, 3, 5, 11),
        exercise: 'Sauna',
        category: 'Passive',
        duration: '0:15:00',
      ),
    ];
    expect(lastWorkoutExercises(history, DateTime(2025, 3, 10, 9)), [
      ('Chest', 'Bench Press'),
      ('Passive', 'Sauna'),
    ]);
  });

  test('a day with only a Sauna entry still counts as the last workout', () {
    final history = [
      WorkoutSet(
        date: DateTime(2025, 3, 5, 10),
        exercise: 'Squat',
        category: 'Legs',
        weight: 200,
        reps: 5,
      ),
      WorkoutSet(
        date: DateTime(2025, 3, 7, 18),
        exercise: 'Sauna',
        category: 'Passive',
        duration: '0:15:00',
      ),
    ];
    expect(lastWorkoutExercises(history, DateTime(2025, 3, 10, 9)), [
      ('Passive', 'Sauna'),
    ]);
  });
}
