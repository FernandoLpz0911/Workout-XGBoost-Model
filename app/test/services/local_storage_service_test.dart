import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
  });
  WorkoutSet strengthSet({
    DateTime? date,
    String exercise = 'Bench Press',
    String category = 'Chest',
    double weight = 135.0,
    int reps = 8,
    String comment = '',
  }) =>
      WorkoutSet(
        date: date ?? DateTime(2026, 1, 15, 10, 0, 0),
        exercise: exercise,
        category: category,
        weight: weight,
        reps: reps,
        comment: comment,
      );
  group('loadAll', () {
    test('returns empty list when storage is empty', () async {
      expect(await storage.loadAll(), isEmpty);
    });
  });

  group('saveAll / loadAll round-trip', () {
    test('persists and restores a strength set', () async {
      final set = strengthSet();
      await storage.saveAll([set]);
      final loaded = await storage.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.exercise, set.exercise);
      expect(loaded.first.weight, set.weight);
      expect(loaded.first.reps, set.reps);
      expect(loaded.first.date.millisecondsSinceEpoch,
          set.date.millisecondsSinceEpoch);
    });

    test('persists and restores a cardio set', () async {
      final set = WorkoutSet(
        date: DateTime(2026, 3, 1),
        exercise: 'General Running',
        category: 'Cardio',
        distance: 3.14,
        distanceUnit: 'mi',
        duration: '0:28:00',
        comment: '',
      );
      await storage.saveAll([set]);
      final loaded = await storage.loadAll();
      expect(loaded.first.distance, closeTo(3.14, 0.001));
      expect(loaded.first.distanceUnit, 'mi');
      expect(loaded.first.duration, '0:28:00');
    });

    test('saveAll overwrites all previously stored sets', () async {
      await storage.saveAll([strengthSet()]);
      final replacement = strengthSet(
        date: DateTime(2026, 2, 1),
        exercise: 'Squat',
        category: 'Legs',
        weight: 200.0,
      );
      await storage.saveAll([replacement]);
      final loaded = await storage.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.exercise, 'Squat');
    });

    test('persists multiple sets in insertion order', () async {
      final sets = [
        strengthSet(date: DateTime(2026, 1, 1)),
        strengthSet(date: DateTime(2026, 1, 2), exercise: 'Squat',
            category: 'Legs', weight: 200, reps: 5),
      ];
      await storage.saveAll(sets);
      final loaded = await storage.loadAll();
      expect(loaded.length, 2);
    });
  });
  group('appendSets', () {
    test('appends to empty storage', () async {
      await storage.appendSets([strengthSet()]);
      expect(await storage.count(), 1);
    });

    test('appends to existing sets without replacing them', () async {
      await storage.saveAll([strengthSet()]);
      final extra = strengthSet(
        date: DateTime(2026, 2, 1),
        exercise: 'Squat',
        category: 'Legs',
        weight: 200.0,
        reps: 5,
      );
      await storage.appendSets([extra]);
      expect(await storage.count(), 2);
    });

    test('appending multiple sets at once works correctly', () async {
      final batch = [
        strengthSet(date: DateTime(2026, 1, 1)),
        strengthSet(date: DateTime(2026, 1, 2), weight: 140.0),
      ];
      await storage.appendSets(batch);
      expect(await storage.count(), 2);
    });
  });
  group('count', () {
    test('returns 0 for empty storage', () async {
      expect(await storage.count(), 0);
    });

    test('returns correct count after saving', () async {
      await storage.saveAll([strengthSet(), strengthSet(weight: 140.0)]);
      expect(await storage.count(), 2);
    });
  });
  group('clear', () {
    test('removes all stored sets', () async {
      await storage.saveAll([strengthSet()]);
      await storage.clear();
      expect(await storage.loadAll(), isEmpty);
    });

    test('clears an already-empty storage without error', () async {
      await storage.clear();
      expect(await storage.count(), 0);
    });
  });
  group('exportAsCsvBytes', () {
    test('produces CSV with the correct FitNotes header', () async {
      await storage.saveAll([strengthSet()]);
      final csv = String.fromCharCodes(await storage.exportAsCsvBytes());
      expect(csv, startsWith(
        'Date,Exercise,Category,Weight,Weight Unit,Reps,'
        'Distance,Distance Unit,Time,Comment',
      ));
    });

    test('CSV contains the stored exercise name and weight', () async {
      await storage.saveAll([strengthSet()]);
      final csv = String.fromCharCodes(await storage.exportAsCsvBytes());
      expect(csv, contains('Bench Press'));
      expect(csv, contains('135.0'));
    });

    test('empty storage produces a header-only CSV', () async {
      final csv = String.fromCharCodes(await storage.exportAsCsvBytes()).trim();
      expect(csv.split('\n').length, 1);
    });
  });
  const validCsv = '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,good session
2026-01-15,Squat,Legs,200.0,lbs,5,,,,
''';

  group('importFromCsvText', () {
    test('imports new rows and returns the count', () async {
      final count = await storage.importFromCsvText(validCsv);
      expect(count, 2);
      expect(await storage.count(), 2);
    });

    test('does not import duplicate rows', () async {
      await storage.importFromCsvText(validCsv);
      final count = await storage.importFromCsvText(validCsv);
      expect(count, 0);
      expect(await storage.count(), 2);
    });

    test('imports only the new rows on a partial overlap', () async {
      const firstBatch = '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
''';
      const secondBatch = '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
2026-01-16,Squat,Legs,200.0,lbs,5,,,,
''';
      await storage.importFromCsvText(firstBatch);
      final count = await storage.importFromCsvText(secondBatch);
      expect(count, 1);
      expect(await storage.count(), 2);
    });

    test('returns 0 for a header-only CSV', () async {
      const headerOnly =
          'Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment\n';
      expect(await storage.importFromCsvText(headerOnly), 0);
    });

    test('skips rows where weight, reps, distance, and duration are all absent',
        () async {
      const emptyRow = '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Mystery,Core,0,lbs,0,,,,"no data"
''';
      expect(await storage.importFromCsvText(emptyRow), 0);
    });

    test('parses comment correctly', () async {
      final loaded = await storage
          .importFromCsvText(validCsv)
          .then((_) => storage.loadAll());
      final bench = loaded.firstWhere((s) => s.exercise == 'Bench Press');
      expect(bench.comment, 'good session');
    });

    test('handles quoted fields that contain commas', () async {
      const csv = '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,"form good, felt strong"
''';
      await storage.importFromCsvText(csv);
      final loaded = await storage.loadAll();
      expect(loaded.first.comment, 'form good, felt strong');
    });

    test('handles escaped double-quotes inside a field', () async {
      const csv = '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,"felt ""great"" today"
''';
      await storage.importFromCsvText(csv);
      final loaded = await storage.loadAll();
      expect(loaded.first.comment, 'felt "great" today');
    });

    test('imports cardio rows with distance and duration', () async {
      const csv = '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-03-01,General Running,Cardio,0,lbs,0,3.14,mi,0:28:00,
''';
      final count = await storage.importFromCsvText(csv);
      expect(count, 1);
      final loaded = await storage.loadAll();
      expect(loaded.first.distance, closeTo(3.14, 0.001));
      expect(loaded.first.distanceUnit, 'mi');
      expect(loaded.first.duration, '0:28:00');
    });

    test('handles Windows-style CRLF line endings', () async {
      final csv =
          'Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment\r\n'
          '2026-01-15,Squat,Legs,200.0,lbs,5,,,,\r\n';
      final count = await storage.importFromCsvText(csv);
      expect(count, 1);
    });
  });
  group('loadTrainingModes', () {
    test('returns empty map when nothing is saved', () async {
      expect(await storage.loadTrainingModes(), isEmpty);
    });
  });

  group('saveTrainingModes / loadTrainingModes round-trip', () {
    test('persists and restores mode assignments', () async {
      await storage.saveTrainingModes({
        'Bench Press': 'strength',
        'Squat': 'hypertrophy',
      });
      final loaded = await storage.loadTrainingModes();
      expect(loaded['Bench Press'], 'strength');
      expect(loaded['Squat'], 'hypertrophy');
    });

    test('overwrites previous mode assignments on re-save', () async {
      await storage.saveTrainingModes({'Bench Press': 'hypertrophy'});
      await storage.saveTrainingModes({'Bench Press': 'strength'});
      final loaded = await storage.loadTrainingModes();
      expect(loaded['Bench Press'], 'strength');
    });

    test('saving an empty map clears all mode assignments', () async {
      await storage.saveTrainingModes({'Bench Press': 'strength'});
      await storage.saveTrainingModes({});
      expect(await storage.loadTrainingModes(), isEmpty);
    });

    test('exercises with no entry are absent (not defaulted by storage)', () async {
      await storage.saveTrainingModes({'Squat': 'strength'});
      final loaded = await storage.loadTrainingModes();
      expect(loaded.containsKey('Bench Press'), isFalse);
    });
  });
}
