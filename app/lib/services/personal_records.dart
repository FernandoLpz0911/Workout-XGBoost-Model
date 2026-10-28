import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/local_recommendation_engine.dart';

/// Dates (each set's unique key) of the sets that were a personal record when
/// logged: heavier than every earlier set of that exercise, or a higher
/// estimated 1RM. Warm-ups, unweighted sets and assisted exercises (where
/// less weight is better) never count.
Set<DateTime> personalRecordDates(List<WorkoutSet> history) {
  final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
  final bestWeight = <String, double>{};
  final best1RM = <String, double>{};
  final prs = <DateTime>{};
  for (final s in sorted) {
    if (s.weight <= 0 || s.reps <= 0) continue;
    if (LocalRecommendationEngine.isAssisted(s.exercise)) continue;
    if (LocalRecommendationEngine.isWarmup(s.comment)) continue;
    final oneRM = LocalRecommendationEngine.calcOneRM(s.weight, s.reps);
    final heavier = s.weight > (bestWeight[s.exercise] ?? 0);
    final stronger = oneRM > (best1RM[s.exercise] ?? 0);
    if (heavier || stronger) prs.add(s.date);
    if (heavier) bestWeight[s.exercise] = s.weight;
    if (stronger) best1RM[s.exercise] = oneRM;
  }
  return prs;
}
