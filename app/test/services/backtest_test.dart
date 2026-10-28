import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/backtest.dart';
import 'package:repiq/services/local_storage_service.dart';

List<WorkoutSet> _linearBench(int sessions) => [
  for (var i = 0; i < sessions; i++)
    for (var set = 0; set < 3; set++)
      WorkoutSet(
        date: DateTime(2025, 1, 1 + i * 3, 10, set),
        exercise: 'Bench Press',
        category: 'Chest',
        weight: 100 + i * 2.5,
        reps: 10,
      ),
];

void main() {
  test('skips the first sessions that have too little history', () {
    final report = runBacktest(_linearBench(2));
    expect(report.count, 0);
  });

  test('a lifter progressing steadily mostly hits the targets', () {
    final report = runBacktest(_linearBench(12));
    expect(report.count, greaterThan(0));
    expect(report.achievedRate, greaterThan(0.7));
    expect(report.tooAggressiveRate, lessThan(0.2));
  });

  test('never predicts from the session being scored', () {
    final report = runBacktest(_linearBench(5));
    for (final p in report.points) {
      expect(p.targetWeight, lessThanOrEqualTo(p.actualWeight + 5));
    }
  });

  // Runs against a real FitNotes export when BACKTEST_CSV points at one:
  //   BACKTEST_CSV=~/Downloads/Data/FitNotes_Export.csv flutter test test/services/backtest_test.dart
  final csvPath = Platform.environment['BACKTEST_CSV'];
  test('real-history backtest report', () {
    final sets = LocalStorageService.parseFitNotesCsv(
      File(csvPath!).readAsStringSync(),
    );
    final report = runBacktest(sets);
    // ignore: avoid_print
    print('BACKTEST $report');
    final perExercise = <String, List<BacktestPoint>>{};
    for (final p in report.points) {
      perExercise.putIfAbsent(p.exercise, () => []).add(p);
    }
    for (final e in perExercise.entries) {
      // ignore: avoid_print
      print('  ${e.key}: ${BacktestReport(e.value)}');
    }
    expect(report.count, greaterThan(0));
  }, skip: csvPath == null ? 'set BACKTEST_CSV to run' : false);
}
