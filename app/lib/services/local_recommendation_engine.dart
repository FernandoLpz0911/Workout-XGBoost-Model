import 'dart:math';
import 'package:repiq/models/recommendation_models.dart';
import 'package:repiq/models/workout_set.dart';

/// Fully offline recommendation engine — mirrors the Python/XGBoost pipeline
/// logic in Dart so the app never needs a network connection.
///
/// All computation is derived from the user's local [WorkoutSet] history.
/// Supports [TrainingMode.hypertrophy] and [TrainingMode.strength] via
/// different rep ranges, weight increments, and graduation thresholds.
class LocalRecommendationEngine {
  /// Estimates 1-rep max using the best formula for the given rep count.
  ///
  /// - Brzycki  for 1–6 reps (accurate at very high intensities)
  /// - Epley    for 7–11 reps (general-purpose)
  /// - Mayhew   for 12+ reps (better at higher rep ranges)
  static double calcOneRM(double weight, int reps) {
    if (reps <= 0 || weight <= 0) return 0;
    if (reps <= 6) return weight / (1.0278 - 0.0278 * reps); // Brzycki
    if (reps <= 11) return weight * (1 + 0.0333 * reps); // Epley
    return (100 * weight) / (52.2 + 41.9 * exp(-0.055 * reps)); // Mayhew
  }

  static double _workingWeight(double oneRM, int reps) =>
      oneRM / (1 + 0.0333 * reps);

  /// Least-squares slope across [ys] — used to detect rising/falling 1RM
  /// momentum over the last three sessions.
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

  static bool _isFormIssue(String c) {
    final s = c.toLowerCase();
    return s.contains('did it wrong') ||
        s.contains('wrong') ||
        s.contains('unsure') ||
        s.contains('too heavy') ||
        s.contains('failed') ||
        s.contains("couldn't") ||
        s.contains("can't complete") ||
        s.contains('sloppy') ||
        s.contains('lost balance') ||
        (s.contains('form is') &&
            (s.contains('off') || s.contains('weird') || s.contains('bad'))) ||
        s.contains('feeling tricep') ||
        s.contains('feeling arm') ||
        s.contains('injury');
  }

  static bool _isFatigue(String c) {
    final s = c.toLowerCase();
    return s.contains('forearm') ||
        s.contains('fatigued') ||
        s.contains('tired') ||
        s.contains('gave out') ||
        s.contains('grip loose') ||
        s.contains('grip gave') ||
        s.contains('grip gone') ||
        s.contains('grip tiring') ||
        s.contains('arms gave') ||
        s.contains('tiring out') ||
        s.contains('limiting');
  }

  static bool _isDropSet(String c) {
    final s = c.toLowerCase();
    return s.contains('dropset') || s.contains('drop set') || s.contains('no rest');
  }

  static bool _isWarmup(String c) {
    final s = c.toLowerCase();
    return s.contains('warmup') || s.contains('warm up') || s.contains('warm-up');
  }

  /// True when the last 4 sessions show no 1RM gain >= 2.5 lbs — indicates a
  /// true plateau rather than normal fluctuation.
  static bool _isPlateaued(List<List<WorkoutSet>> sessions) {
    final rms = sessions
        .map((s) => s.map((w) => calcOneRM(w.weight, w.reps)).reduce(max))
        .toList();
    return rms.reduce(max) - rms.first < 2.5;
  }

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

  /// Returns a [Recommendation] for [exercise] given the user's full history.
  ///
  /// The [mode] parameter selects between hypertrophy and strength progressions.
  /// Drop sets and warm-up sets are excluded before any computation.
  static Recommendation recommend({
    required String exercise,
    required String category,
    required List<WorkoutSet> allHistory,
    TrainingMode mode = TrainingMode.hypertrophy,
  }) {
    // Hypertrophy: moderate weight, 8–12 rep range, +2.5 lb jumps
    // Strength:    heavy weight,    3–6 rep range,  +5.0 lb jumps
    final bool isStrength = mode == TrainingMode.strength;
    final int defaultReps = isStrength ? 5 : 10;
    final int graduationReps = isStrength ? 6 : 12;
    final int volumeTargetReps = isStrength ? 6 : 12;
    final int stabilizeReps = isStrength ? 4 : 10;
    final int stabilizeThreshold = isStrength ? 3 : 8;
    final double weightIncrement = isStrength ? 5.0 : 2.5;
    final String modeLabel = isStrength ? 'STRENGTH' : 'HYPERTROPHY';

    final raw =
        allHistory
            .where((s) => s.exercise == exercise)
            .where((s) => !_isDropSet(s.comment) && !_isWarmup(s.comment))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    if (raw.isEmpty) {
      return Recommendation(
        targetReps: defaultReps,
        targetWeight: 0.0,
        status: 'NEW EXERCISE: No history — log your first sets',
        predicted1RM: 0,
        required1RM: 0,
        notesInsight:
            'No sets logged for this exercise yet. Start conservative and build up.',
      );
    }

    final sessions = _groupBySessions(raw);

    // Exclude intra-session warm-up weights: any set below 60 % of that
    // session's top weight is likely a warm-up that would inflate rep counts.
    final workingSessions = sessions
        .map((sess) {
          final maxW = sess.map((s) => s.weight).reduce(max);
          return sess
              .where((s) => maxW == 0 || s.weight >= 0.6 * maxW)
              .toList();
        })
        .where((sess) => sess.isNotEmpty)
        .toList();

    if (workingSessions.isEmpty) {
      return Recommendation(
        targetReps: defaultReps,
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
        lastSess.map((s) => s.reps).reduce((a, b) => a + b) / lastSess.length;
    final last1RM = lastSess
        .map((s) => calcOneRM(s.weight, s.reps))
        .reduce(max);
    final hadFormIssue = lastSess.any((s) => _isFormIssue(s.comment));
    final hadFatigue = lastSess.any((s) => _isFatigue(s.comment));

    // Linear slope over the last 3 sessions — positive means the 1RM is
    // climbing, negative means it's declining (possible overtraining signal).
    final recentSessions = workingSessions.length >= 3
        ? workingSessions.sublist(workingSessions.length - 3)
        : workingSessions;
    final recent1RMs = recentSessions
        .map((sess) => sess.map((s) => calcOneRM(s.weight, s.reps)).reduce(max))
        .toList();
    final momentum = _slope(recent1RMs);

    // Rep consistency: a ratio < 0.5 means reps collapsed across sets
    // (e.g. 10 → 7 → 3), suggesting the weight was too heavy to sustain.
    final repVals = lastSess.map((s) => s.reps.toDouble()).toList();
    final repConsistency = repVals.length > 1
        ? (repVals.reduce(min) /
                  (repVals.reduce((a, b) => a + b) / repVals.length))
              .clamp(0.0, 1.0)
        : 1.0;

    double targetWeight;
    int targetReps;
    String baseStatus;

    final plateauDetected =
        workingSessions.length >= 4 &&
        _isPlateaued(workingSessions.sublist(workingSessions.length - 4));

    if (hadFormIssue) {
      targetWeight = lastMaxW;
      targetReps = defaultReps;
      baseStatus = 'FORM FOCUS: Repeat weight to nail technique';
    } else if (plateauDetected) {
      targetWeight = ((lastMaxW * 0.6) / 2.5).round() * 2.5;
      targetReps = 15;
      baseStatus =
          'DELOAD: Plateau detected — back off to rebuild work capacity';
    } else if (lastAvgReps >= graduationReps) {
      targetWeight = lastMaxW + weightIncrement;
      targetReps = defaultReps;
      baseStatus = '$modeLabel PROGRESSION: Weight Increased';
    } else if (lastAvgReps < stabilizeThreshold) {
      targetWeight = lastMaxW;
      targetReps = stabilizeReps;
      baseStatus = '$modeLabel STABILIZATION: Build rep count first';
    } else {
      targetWeight = lastMaxW;
      targetReps = volumeTargetReps;
      baseStatus = '$modeLabel VOLUME: Push for $volumeTargetReps reps';
    }

    // Category-specific safety floors: larger muscle groups (Legs, Chest, Back)
    // need a higher capacity threshold before adding weight because the load is
    // heavier and injury risk is greater than for smaller groups (Arms).
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
      targetReps = (lastAvgReps >= graduationReps)
          ? volumeTargetReps + 3
          : defaultReps;
      status = 'BODYWEIGHT: Add reps to progress';
    } else if (momentum < -2.0 && last1RM < required1RM * threshold) {
      // Declining trend combined with an ambitious target — pull back weight
      // to stay within the safety threshold rather than risk regression/injury.
      var adjusted = (_workingWeight(last1RM, targetReps) / 2.5).round() * 2.5;
      if (adjusted <= 0) adjusted = lastMaxW;
      targetWeight = adjusted.toDouble();
      status = 'AI OVERRIDE: Declining trend — weight adjusted for safety';
    } else if (repConsistency < 0.5 && !hadFormIssue) {
      targetWeight = lastMaxW;
      targetReps = defaultReps;
      status = 'STABILIZATION: Rep drop detected — build consistency';
    } else {
      status = baseStatus;
    }

    final insights = <String>[];
    if (hadFormIssue) {
      insights.add(
        'Form issues were logged last session — prioritize technique over load today.',
      );
    }
    if (plateauDetected) {
      insights.add(
        'No 1RM gain across the last 4 sessions. Deload at 60% load with higher reps to rebuild capacity and break through.',
      );
    }
    if (hadFatigue) {
      insights.add(
        'Grip or muscle fatigue was logged last session — '
        'consider a grip aid or an extra rest day.',
      );
    }
    if (momentum < -2.0) {
      insights.add(
        '1RM has been declining recently — a deload or extra recovery may help.',
      );
    } else if (momentum > 5.0) {
      insights.add(
        'Strong momentum — your 1RM has been climbing consistently!',
      );
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
