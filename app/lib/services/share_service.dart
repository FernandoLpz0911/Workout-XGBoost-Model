import 'package:share_plus/share_plus.dart';
import 'package:repiq/models/workout_set.dart';

/// Formats one day's logged sets as shareable plain text and hands off to
/// the OS share sheet.
class ShareService {
  static Future<void> shareDay(String dateLabel, List<WorkoutSet> sets) async {
    final byExercise = <String, List<WorkoutSet>>{};
    for (final s in sets) {
      byExercise.putIfAbsent(s.exercise, () => []).add(s);
    }

    final buf = StringBuffer()
      ..writeln(dateLabel)
      ..writeln();
    for (final entry in byExercise.entries) {
      buf.writeln(entry.key);
      for (final s in entry.value) {
        final note = s.comment.isNotEmpty ? ' — "${s.comment}"' : '';
        buf.writeln('${s.displayText}$note');
      }
      buf.writeln();
    }

    await Share.share(buf.toString().trim(), subject: 'Workout — $dateLabel');
  }
}
