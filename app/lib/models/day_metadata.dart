/// Whole-day metadata — a comment and/or a start/end time for a workout day.
/// Distinct from per-set [WorkoutSet.comment].
class DayMetadata {
  final String comment;

  /// Stored as 24-hour "HH:mm", locale-agnostic.
  final String? startTime;
  final String? endTime;

  const DayMetadata({this.comment = '', this.startTime, this.endTime});

  bool get isEmpty => comment.isEmpty && startTime == null && endTime == null;

  Map<String, dynamic> toJson() => {
    'comment': comment,
    if (startTime != null) 'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
  };

  factory DayMetadata.fromJson(Map<String, dynamic> j) => DayMetadata(
    comment: j['comment'] as String? ?? '',
    startTime: j['startTime'] as String?,
    endTime: j['endTime'] as String?,
  );
}
