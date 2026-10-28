import 'package:repiq/models/workout_set.dart';

/// The exercises of the most recent workout before [today], in the order
/// they were first performed, as `(category, exercise)` pairs. Empty when
/// there is no earlier workout.
List<(String, String)> lastWorkoutExercises(
  List<WorkoutSet> history,
  DateTime today,
) {
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  final earlier = history.where((s) => !sameDay(s.date, today)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  if (earlier.isEmpty) return const [];
  final lastDay = earlier.last.date;
  final seen = <(String, String)>{};
  for (final s in earlier.where((s) => sameDay(s.date, lastDay))) {
    seen.add((s.category, s.exercise));
  }
  return seen.toList();
}
