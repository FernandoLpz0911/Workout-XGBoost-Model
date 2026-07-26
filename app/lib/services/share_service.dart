import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:repiq/models/weight_unit.dart';
import 'package:repiq/models/workout_set.dart';

/// Formats one day's logged sets as shareable plain text and hands off to
/// the OS share sheet.
class ShareService {
  /// Hands the full FitNotes-compatible CSV export off to the OS share
  /// sheet, so the user can save it to Drive/Files, email it, etc. for
  /// analysis outside the app.
  static Future<void> shareCsvExport(Uint8List csvBytes) async {
    final file = XFile.fromData(
      csvBytes,
      name: 'repiq_export_${DateTime.now().millisecondsSinceEpoch}.csv',
      mimeType: 'text/csv',
    );
    await Share.shareXFiles([file], subject: 'RepIQ Workout Export');
  }

  static Future<void> shareDay(
    String dateLabel,
    List<WorkoutSet> sets, {
    WeightUnit unit = WeightUnit.lbs,
  }) async {
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
        buf.writeln('${s.displayTextIn(unit)}$note');
      }
      buf.writeln();
    }

    await Share.share(buf.toString().trim(), subject: 'Workout — $dateLabel');
  }
}
