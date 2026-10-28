import 'package:repiq/models/workout_set.dart';

/// The `(category, exercise)` with the most distinct session days among
/// strength sets (weight and reps > 0) in [categories]; ties go to the one
/// logged most recently. Null when there is none.
(String, String)? mostLoggedExercise(
  List<WorkoutSet> history,
  Set<String> categories,
) {
  final days = <(String, String), Set<String>>{};
  final latest = <(String, String), DateTime>{};
  for (final s in history) {
    if (s.weight <= 0 || s.reps <= 0 || !categories.contains(s.category)) {
      continue;
    }
    final key = (s.category, s.exercise);
    days.putIfAbsent(key, () => {}).add(WorkoutSet.fmtDateStatic(s.date));
    final prev = latest[key];
    if (prev == null || s.date.isAfter(prev)) latest[key] = s.date;
  }
  (String, String)? best;
  for (final key in days.keys) {
    if (best == null) {
      best = key;
      continue;
    }
    final c = days[key]!.length.compareTo(days[best]!.length);
    if (c > 0 || (c == 0 && latest[key]!.isAfter(latest[best]!))) best = key;
  }
  return best;
}
