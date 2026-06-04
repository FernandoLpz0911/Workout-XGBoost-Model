/// A single logged entry — one set, lap, or passive session.
///
/// Covers three exercise types:
/// - **Strength**: [weight] + [reps]
/// - **Cardio**: [distance] + [distanceUnit] + optional [duration]
/// - **Passive**: [duration] only (sauna, stretching, foam rolling, etc.)
class WorkoutSet {
  /// Timestamp when this entry was logged.
  ///
  /// Stored as full ISO 8601 (including milliseconds) so it can serve as a
  /// primary key for edit and delete operations.
  final DateTime date;

  final String exercise;
  final String category;

  /// Weight lifted in lbs. 0 for bodyweight or non-strength exercises.
  final double weight;

  /// Reps completed. 0 for non-strength exercises.
  final int reps;

  /// Distance covered. Non-null only for cardio exercises.
  final double? distance;

  /// Distance unit: `"mi"` or `"km"`. Non-null when [distance] is set.
  final String? distanceUnit;

  /// Duration in `"H:MM:SS"` format. Used by cardio (lap time), passive
  /// (session time), and time-based strength exercises such as Dead Hang.
  final String? duration;

  final String comment;

  const WorkoutSet({
    required this.date,
    required this.exercise,
    required this.category,
    this.weight = 0.0,
    this.reps = 0,
    this.distance,
    this.distanceUnit,
    this.duration,
    this.comment = '',
  });

  Map<String, dynamic> toJson() => {
        // Full ISO 8601 so we can match by exact millisecond on delete/edit
        'date': date.toIso8601String(),
        'exercise': exercise,
        'category': category,
        'weight': weight,
        'reps': reps,
        if (distance != null) 'distance': distance,
        if (distanceUnit != null) 'distanceUnit': distanceUnit,
        if (duration != null) 'duration': duration,
        'comment': comment,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> j) => WorkoutSet(
        // Accepts both full ISO ("2026-05-28T14:30:00") and date-only ("2026-05-28")
        date: DateTime.parse(j['date'] as String),
        exercise: j['exercise'] as String,
        category: j['category'] as String,
        weight: (j['weight'] as num?)?.toDouble() ?? 0.0,
        reps: j['reps'] as int? ?? 0,
        distance: (j['distance'] as num?)?.toDouble(),
        distanceUnit: j['distanceUnit'] as String?,
        duration: j['duration'] as String?,
        comment: j['comment'] as String? ?? '',
      );

  /// Returns a FitNotes-compatible CSV row for this set.
  String toCsvRow() {
    final d = _fmtDate(date);
    final w = weight > 0 ? weight.toStringAsFixed(1) : '';
    final wUnit = weight > 0 ? 'lbs' : '';
    final r = reps > 0 ? reps.toString() : '';
    final dist =
        (distance != null && distance! > 0) ? distance!.toStringAsFixed(2) : '';
    final dUnit =
        (distance != null && distance! > 0) ? (distanceUnit ?? 'mi') : '';
    final dur = duration ?? '';
    final c = comment.replaceAll('"', '""');
    return '$d,$exercise,$category,$w,$wUnit,$r,$dist,$dUnit,$dur,"$c"';
  }

  /// Human-readable summary shown in the log and history UI.
  String get displayText {
    if (duration != null && weight == 0 && reps == 0 && distance == null) {
      return duration!;
    }
    if (distance != null && distance! > 0) {
      final unit = distanceUnit ?? 'mi';
      if (duration != null) return '${distance!.toStringAsFixed(2)} $unit @ $duration';
      return '${distance!.toStringAsFixed(2)} $unit';
    }
    return '${weight.toStringAsFixed(1)} lbs × $reps';
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String fmtDateStatic(DateTime d) => _fmtDate(d);
}
