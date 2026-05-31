import 'dart:math';
import '../models/recommendation_models.dart';
import '../models/workout_set.dart';

/// Fully offline recommendation engine — mirrors the Python pipeline logic in Dart.
///
/// No network calls. All computation is derived from the user's local history.
class LocalRecommendationEngine {
  // ── 1RM formulas (same as pipeline.py) ───────────────────────────────────

  static double calcOneRM(double weight, int reps) {
    if (reps <= 0 || weight <= 0) return 0;
    if (reps <= 6) return weight / (1.0278 - 0.0278 * reps);    // Brzycki
    if (reps <= 11) return weight * (1 + 0.0333 * reps);        // Epley
    return (100 * weight) / (52.2 + 41.9 * exp(-0.055 * reps)); // Mayhew
  }

  static double _workingWeight(double oneRM, int reps) =>
      oneRM / (1 + 0.0333 * reps);

  // ── Linear slope (for 1RM momentum over last N sessions) ─────────────────

  static double _slope(List<double> ys) {
    if (ys.length < 2) return 0.0;
    final n = ys.length.toDouble();
    final xMean = (n - 1) / 2.0;
    final yMean = ys.reduce((a, b) => a + b) / n;
    double num = 0, den = 0;
    for (int i = 0; i < ys.length; i++) {
      num += (i - xMean) * (ys[i] - yMean);
      den += (i - xMean) * (i - xMean);
    }
    return den == 0 ? 0.0 : num / den;
  }

  // ── Comment signal detection (same patterns as pipeline.py) ──────────────
  // Using Pattern + String.contains() avoids the RegExp deprecation lint.

  static final Pattern _formIssueRe = RegExp(
    r"did it wrong|wrong|unsure|too heavy|failed|couldn't|sloppy|"
    r'lost balance|form is\s*(off|weird|bad)|injury',
    caseSensitive: false,
  );
  static final Pattern _fatigueRe = RegExp(
    r'forearm|fatigued|tired|gave out|grip\s*(loose|gave|gone|tiring)|'
    r'arms gave|tiring out',
    caseSensitive: false,
  );
  static final Pattern _dropSetRe =
      RegExp(r'drop\s*set|no rest', caseSensitive: false);
  static final Pattern _warmupRe =
      RegExp(r'warm[\s-]?up', caseSensitive: false);

  static bool _isFormIssue(String c) => c.contains(_formIssueRe);
  static bool _isFatigue(String c) => c.contains(_fatigueRe);
  static bool _isDropSet(String c) => c.contains(_dropSetRe);
  static bool _isWarmup(String c) => c.contains(_warmupRe);

  // ── Session grouping ──────────────────────────────────────────────────────

  static List<List<WorkoutSet>> _groupBySessions(List<WorkoutSet> sets) {
    final map = <String, List<WorkoutSet>>{};
    for (final s in sets) {
      final key =
          '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-'
          '${s.date.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(s);
    }
    final sortedKeys = map.keys.toList()..sort();
    return sortedKeys.map((k) => map[k]!).toList();
  }

  // ── Main recommendation ───────────────────────────────────────────────────

  static Recommendation recommend({
    required String exercise,
    required String category,
    required List<WorkoutSet> allHistory,
  }) {
    // Filter to this exercise, excluding drop sets and warm-up sets
    final raw = allHistory
        .where((s) => s.exercise == exercise)
        .where((s) => !_isDropSet(s.comment) && !_isWarmup(s.comment))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (raw.isEmpty) {
      return const Recommendation(
        targetReps: 8,
        targetWeight: 0.0,
        status: 'NEW EXERCISE: No history — log your first sets',
        predicted1RM: 0,
        required1RM: 0,
        notesInsight:
            'No sets logged for this exercise yet. Start conservative and build up.',
      );
    }

    final sessions = _groupBySessions(raw);

    // Remove weight-based warm-ups: sets < 60% of session max weight
    final workingSessions = sessions.map((sess) {
      final maxW = sess.map((s) => s.weight).reduce(max);
      return sess
          .where((s) => maxW == 0 || s.weight >= 0.6 * maxW)
          .toList();
    }).where((sess) => sess.isNotEmpty).toList();

    if (workingSessions.isEmpty) {
      return const Recommendation(
        targetReps: 8,
        targetWeight: 45.0,
        status: 'BASELINE: Insufficient quality sets found',
        predicted1RM: 0,
        required1RM: 0,
        notesInsight: '',
      );
    }

    final lastSess = workingSessions.last;
    final lastMaxW = lastSess.map((s) => s.weight).reduce(max);
    final lastAvgReps =
        lastSess.map((s) => s.reps).reduce((a, b) => a + b) /
            lastSess.length;
    final last1RM =
        lastSess.map((s) => calcOneRM(s.weight, s.reps)).reduce(max);
    final hadFormIssue = lastSess.any((s) => _isFormIssue(s.comment));
    final hadFatigue = lastSess.any((s) => _isFatigue(s.comment));

    // 1RM momentum: linear slope over last 3 sessions
    final recentSessions = workingSessions.length >= 3
        ? workingSessions.sublist(workingSessions.length - 3)
        : workingSessions;
    final recent1RMs = recentSessions
        .map((sess) =>
            sess.map((s) => calcOneRM(s.weight, s.reps)).reduce(max))
        .toList();
    final momentum = _slope(recent1RMs);

    // Rep consistency: did reps collapse across sets last session?
    final repVals = lastSess.map((s) => s.reps.toDouble()).toList();
    final repConsistency = repVals.length > 1
        ? (repVals.reduce(min) /
                (repVals.reduce((a, b) => a + b) / repVals.length))
            .clamp(0.0, 1.0)
        : 1.0;

    // ── Progression decision ──────────────────────────────────────────────

    double targetWeight;
    int targetReps;
    String baseStatus;

    if (hadFormIssue) {
      targetWeight = lastMaxW;
      targetReps = 8;
      baseStatus = 'FORM FOCUS: Repeat weight to nail technique';
    } else if (lastAvgReps >= 10) {
      targetWeight = lastMaxW + 2.5;
      targetReps = 8;
      baseStatus = 'PROGRESSION: Weight Increased';
    } else if (lastAvgReps < 6) {
      targetWeight = lastMaxW;
      targetReps = 8;
      baseStatus = 'STABILIZATION: Build rep count first';
    } else {
      targetWeight = lastMaxW;
      targetReps = 10;
      baseStatus = 'VOLUME: Push for graduation threshold';
    }

    const thresholds = <String, double>{
      'Legs': 0.95,
      'Chest': 0.95,
      'Back': 0.95,
      'Shoulders': 0.90,
      'Arms': 0.85,
    };
    final threshold = thresholds[category] ?? 0.95;
    final required1RM = targetWeight * (1 + 0.0333 * targetReps);
    String status;

    if (lastMaxW == 0) {
      // Bodyweight exercise — progress via reps
      targetReps = (lastAvgReps >= 10) ? 12 : 8;
      status = 'BODYWEIGHT: Add reps to progress';
    } else if (momentum < -2.0 && last1RM < required1RM * threshold) {
      // Declining trend + ambitious target → pull back
      var adjusted = (_workingWeight(last1RM, targetReps) / 2.5).round() * 2.5;
      if (adjusted <= 0) adjusted = lastMaxW;
      targetWeight = adjusted.toDouble();
      status = 'AI OVERRIDE: Declining trend — weight adjusted for safety';
    } else if (repConsistency < 0.5 && !hadFormIssue) {
      // Reps collapsed (e.g. 10→7→3) — stabilise before progressing
      targetWeight = lastMaxW;
      targetReps = 8;
      status = 'STABILIZATION: Rep drop detected — build consistency';
    } else {
      status = baseStatus;
    }

    // ── Notes insight ─────────────────────────────────────────────────────

    final insights = <String>[];
    if (hadFormIssue) {
      insights.add(
          'Form issues were logged last session — prioritize technique over load today.');
    }
    if (hadFatigue) {
      insights.add(
          'Grip or muscle fatigue was logged last session — '
          'consider a grip aid or an extra rest day.');
    }
    if (momentum < -2.0) {
      insights.add(
          '1RM has been declining recently — a deload or extra recovery may help.');
    } else if (momentum > 5.0) {
      insights.add(
          'Strong momentum — your 1RM has been climbing consistently!');
    }

    return Recommendation(
      targetReps: targetReps,
      targetWeight: targetWeight,
      status: status,
      predicted1RM: last1RM,
      required1RM: required1RM,
      notesInsight: insights.join(' '),
    );
  }
}
