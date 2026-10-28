import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/progress_defaults.dart';

WorkoutSet _s(DateTime d, String ex, String cat, {double w = 100}) =>
    WorkoutSet(date: d, exercise: ex, category: cat, weight: w, reps: 5);

void main() {
  test('empty history gives null', () {
    expect(mostLoggedExercise([], {'X'}), isNull);
  });

  test('picks exercise with most distinct days, not most sets', () {
    final h = [
      for (var i = 0; i < 10; i++) _s(DateTime(2025, 1, 1, 10, i), 'A', 'X'),
      _s(DateTime(2025, 1, 2), 'B', 'Y'),
      _s(DateTime(2025, 1, 3), 'B', 'Y'),
    ];
    expect(mostLoggedExercise(h, {'X', 'Y'}), ('Y', 'B'));
  });

  test('ties go to most recent', () {
    final h = [
      _s(DateTime(2025, 1, 1), 'A', 'X'),
      _s(DateTime(2025, 2, 1), 'B', 'Y'),
    ];
    expect(mostLoggedExercise(h, {'X', 'Y'}), ('Y', 'B'));
  });

  test('ignores non-strength sets and disallowed categories', () {
    final h = [
      _s(DateTime(2025, 1, 1), 'A', 'X', w: 0),
      _s(DateTime(2025, 1, 2), 'A', 'X', w: 0),
      _s(DateTime(2025, 1, 3), 'B', 'Y'),
      _s(DateTime(2025, 1, 4), 'C', 'Z'),
      _s(DateTime(2025, 1, 5), 'C', 'Z'),
    ];
    expect(mostLoggedExercise(h, {'X', 'Y'}), ('Y', 'B'));
  });
}
