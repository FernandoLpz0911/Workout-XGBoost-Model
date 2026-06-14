/// Whether an exercise is targeted for muscle growth or maximum strength.
///
/// Controls rep ranges, weight increments, and graduation thresholds inside
/// [LocalRecommendationEngine].
enum TrainingMode {
  /// Moderate weight, 8–12 rep range, +2.5 lb increments per progression.
  hypertrophy,

  /// Heavy weight, 3–6 rep range, +5.0 lb increments per progression.
  strength,
}

/// AI-generated recommendation for a single exercise session.
class Recommendation {
  /// Suggested number of reps per set.
  final int targetReps;

  /// Suggested working weight in lbs.
  final double targetWeight;

  /// Short status label shown in the UI (e.g. "STRENGTH PROGRESSION: Weight Increased").
  final String status;

  /// Estimated 1-rep max derived from the most recent session.
  final double predicted1RM;

  /// The 1RM required to safely handle [targetWeight] at [targetReps].
  final double required1RM;

  /// Contextual insight derived from logged comments — form issues, fatigue,
  /// or momentum signals. Empty string when nothing notable was detected.
  final String notesInsight;

  const Recommendation({
    required this.targetReps,
    required this.targetWeight,
    required this.status,
    required this.predicted1RM,
    required this.required1RM,
    this.notesInsight = '',
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
    targetReps: json['target_reps'] as int,
    targetWeight: (json['target_weight'] as num).toDouble(),
    status: json['status'] as String,
    predicted1RM: (json['predicted_1rm'] as num).toDouble(),
    required1RM: (json['required_1rm'] as num).toDouble(),
    notesInsight: json['notes_insight'] as String? ?? '',
  );
}
