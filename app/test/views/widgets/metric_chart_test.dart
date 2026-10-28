import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/views/widgets/metric_chart.dart';

void main() {
  test('computeExerciseSeries ignores warm-up sets', () {
    WorkoutSet set(double w, int r, [String comment = '']) => WorkoutSet(
      date: DateTime(2026, 10, 28, 10),
      exercise: 'Incline Dumbbell Bench Press',
      category: 'Chest',
      weight: w,
      reps: r,
      comment: comment,
    );
    final history = [
      set(20, 8, 'Warmup'),
      set(30, 4, 'Warmup'),
      set(35, 10),
      set(35, 10),
    ];

    final volume = computeExerciseSeries(
      history,
      'Incline Dumbbell Bench Press',
      'Volume',
      null,
    );
    expect(volume.single.value, 700);
  });
}
