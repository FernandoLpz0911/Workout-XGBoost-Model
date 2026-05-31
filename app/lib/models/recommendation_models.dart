class Recommendation {
  final int targetReps;
  final double targetWeight;
  final String status;
  final double predicted1RM;
  final double required1RM;
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
