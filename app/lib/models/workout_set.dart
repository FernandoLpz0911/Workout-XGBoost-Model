class WorkoutSet {
  final DateTime date;
  final String exercise;
  final String category;

  // Strength fields (0 for non-strength)
  final double weight;
  final int reps;

  // Cardio fields (null for non-cardio)
  final double? distance;
  final String? distanceUnit; // "mi" or "km"

  // Duration: used by cardio (lap time), passive (session time),
  // and time-based strength (Dead Hang etc.)  Format: "H:MM:SS"
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

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        // Full ISO 8601 so we can match by exact millisecond on delete
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
        // Handles both full ISO ("2026-05-28T14:30:00") and date-only ("2026-05-28")
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

  // ── FitNotes-compatible CSV row ────────────────────────────────────────────

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

  // ── Human-readable one-liner for UI display ───────────────────────────────

  String get displayText {
    // Time-based (Dead Hang, Sauna, etc.)
    if (duration != null && weight == 0 && reps == 0 && distance == null) {
      return duration!;
    }
    // Cardio (distance + optional pace)
    if (distance != null && distance! > 0) {
      final unit = distanceUnit ?? 'mi';
      if (duration != null) return '${distance!.toStringAsFixed(2)} $unit @ $duration';
      return '${distance!.toStringAsFixed(2)} $unit';
    }
    // Strength
    return '${weight.toStringAsFixed(1)} lbs × $reps';
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String fmtDateStatic(DateTime d) => _fmtDate(d);
}
