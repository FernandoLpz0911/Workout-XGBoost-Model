import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/local_recommendation_engine.dart';

/// How one recommendation compared to the session that actually followed it.
class BacktestPoint {
  final String exercise;
  final DateTime date;
  final double targetWeight;
  final int targetReps;

  /// Heaviest weight lifted in the session being predicted.
  final double actualWeight;

  /// Most reps done at or above [targetWeight] (0 if never reached).
  final int repsAtTarget;

  /// Best estimated 1RM of the session vs. the 1RM the target implied.
  final double actualBest1RM;
  final double target1RM;

  const BacktestPoint({
    required this.exercise,
    required this.date,
    required this.targetWeight,
    required this.targetReps,
    required this.actualWeight,
    required this.repsAtTarget,
    required this.actualBest1RM,
    required this.target1RM,
  });

  /// The lifter matched or beat the strength the target asked for. Scored
  /// by estimated 1RM, since history wasn't logged while following the app:
  /// 105x10 meets a 102.5x11 target even though the reps differ. The 2%
  /// slack absorbs rounding between the 1RM formulas.
  bool get achieved => actualBest1RM >= target1RM * 0.98;

  /// The target asked for more than 5% beyond what the lifter could show.
  bool get tooAggressive => target1RM > actualBest1RM * 1.05;

  double get weightError => (targetWeight - actualWeight).abs();
}

class BacktestReport {
  final List<BacktestPoint> points;
  const BacktestReport(this.points);

  int get count => points.length;

  double _rate(bool Function(BacktestPoint) f) =>
      points.isEmpty ? 0 : points.where(f).length / points.length;

  double get achievedRate => _rate((p) => p.achieved);
  double get tooAggressiveRate => _rate((p) => p.tooAggressive);

  double get meanAbsWeightError => points.isEmpty
      ? 0
      : points.map((p) => p.weightError).reduce((a, b) => a + b) /
            points.length;

  @override
  String toString() =>
      'predictions=$count '
      'achieved=${(achievedRate * 100).toStringAsFixed(1)}% '
      'tooAggressive=${(tooAggressiveRate * 100).toStringAsFixed(1)}% '
      'meanAbsWeightError=${meanAbsWeightError.toStringAsFixed(1)} lbs';
}

/// Replays [history] session by session: for every weighted exercise
/// session after the [minPriorSessions]th, asks the engine for a
/// recommendation using only earlier sets, then scores it against what was
/// actually lifted that day.
BacktestReport runBacktest(
  List<WorkoutSet> history, {
  int minPriorSessions = 2,
}) {
  final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
  String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  // exercise -> day -> sets, in chronological order.
  final byExercise = <String, Map<String, List<WorkoutSet>>>{};
  for (final s in sorted) {
    if (s.weight <= 0 || s.reps <= 0) continue;
    byExercise
        .putIfAbsent(s.exercise, () => {})
        .putIfAbsent(dayKey(s.date), () => [])
        .add(s);
  }

  final points = <BacktestPoint>[];
  for (final entry in byExercise.entries) {
    final sessions = entry.value.values.toList();
    for (var i = minPriorSessions; i < sessions.length; i++) {
      final session = sessions[i];
      final cutoff = session.first.date;
      final prior = sorted.where((s) => s.date.isBefore(cutoff)).toList();
      final rec = LocalRecommendationEngine.recommend(
        exercise: entry.key,
        category: session.first.category,
        allHistory: prior,
      );
      if (rec.targetWeight <= 0 || rec.targetReps <= 0) continue;

      final repsAtTarget = session
          .where((s) => s.weight >= rec.targetWeight)
          .fold<int>(0, (m, s) => s.reps > m ? s.reps : m);
      points.add(
        BacktestPoint(
          exercise: entry.key,
          date: cutoff,
          targetWeight: rec.targetWeight,
          targetReps: rec.targetReps,
          actualWeight: session
              .map((s) => s.weight)
              .reduce((a, b) => a > b ? a : b),
          repsAtTarget: repsAtTarget,
          actualBest1RM: session
              .map((s) => LocalRecommendationEngine.calcOneRM(s.weight, s.reps))
              .reduce((a, b) => a > b ? a : b),
          target1RM: LocalRecommendationEngine.calcOneRM(
            rec.targetWeight,
            rec.targetReps,
          ),
        ),
      );
    }
  }
  return BacktestReport(points);
}
