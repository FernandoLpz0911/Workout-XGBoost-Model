import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:repiq/models/body_measurement.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalStorageService storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService(dbPath: inMemoryDatabasePath);
  });

  tearDown(() async {
    await storage.close();
  });
  WorkoutSet strengthSet({
    DateTime? date,
    String exercise = 'Bench Press',
    String category = 'Chest',
    double weight = 135.0,
    int reps = 8,
    String comment = '',
  }) => WorkoutSet(
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

  group('appendSets / loadAll round-trip', () {
    test('persists and restores a strength set', () async {
      final set = strengthSet();
      await storage.appendSets([set]);
      final loaded = await storage.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.exercise, set.exercise);
      expect(loaded.first.weight, set.weight);
      expect(loaded.first.reps, set.reps);
      expect(
        loaded.first.date.millisecondsSinceEpoch,
        set.date.millisecondsSinceEpoch,
      );
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
      await storage.appendSets([set]);
      final loaded = await storage.loadAll();
      expect(loaded.first.distance, closeTo(3.14, 0.001));
      expect(loaded.first.distanceUnit, 'mi');
      expect(loaded.first.duration, '0:28:00');
    });

    test('clear then appendSets replaces stored sets', () async {
      await storage.appendSets([strengthSet()]);
      await storage.clear();
      final replacement = strengthSet(
        date: DateTime(2026, 2, 1),
        exercise: 'Squat',
        category: 'Legs',
        weight: 200.0,
      );
      await storage.appendSets([replacement]);
      final loaded = await storage.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.exercise, 'Squat');
    });

    test('persists multiple sets in insertion order', () async {
      final sets = [
        strengthSet(date: DateTime(2026, 1, 1)),
        strengthSet(
          date: DateTime(2026, 1, 2),
          exercise: 'Squat',
          category: 'Legs',
          weight: 200,
          reps: 5,
        ),
      ];
      await storage.appendSets(sets);
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
      await storage.appendSets([strengthSet()]);
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
      await storage.appendSets([strengthSet(), strengthSet(weight: 140.0)]);
      expect(await storage.count(), 2);
    });
  });
  group('clear', () {
    test('removes all stored sets', () async {
      await storage.appendSets([strengthSet()]);
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
      await storage.appendSets([strengthSet()]);
      final csv = String.fromCharCodes(await storage.exportAsCsvBytes());
      expect(
        csv,
        startsWith(
          'Date,Exercise,Category,Weight,Weight Unit,Reps,'
          'Distance,Distance Unit,Time,Comment',
        ),
      );
    });

    test('CSV contains the stored exercise name and weight', () async {
      await storage.appendSets([strengthSet()]);
      final csv = String.fromCharCodes(await storage.exportAsCsvBytes());
      expect(csv, contains('Bench Press'));
      expect(csv, contains('135.0'));
    });

    test('empty storage produces a header-only CSV', () async {
      final csv = String.fromCharCodes(await storage.exportAsCsvBytes()).trim();
      expect(csv.split('\n').length, 1);
    });
  });
  const validCsv =
      '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
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
      const firstBatch =
          '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
''';
      const secondBatch =
          '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
2026-01-16,Squat,Legs,200.0,lbs,5,,,,
''';
      await storage.importFromCsvText(firstBatch);
      final count = await storage.importFromCsvText(secondBatch);
      expect(count, 1);
      expect(await storage.count(), 2);
    });

    test('imports identical straight sets on the same day without dropping '
        'duplicates', () async {
      // FitNotes only exports a day-level date, so three ordinary
      // straight sets (same exercise, weight, reps, same day) would
      // previously collide on the day-level fingerprint and only the
      // first would survive the import.
      const csv =
          '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
''';
      final count = await storage.importFromCsvText(csv);
      expect(count, 3);
      expect(await storage.count(), 3);
    });

    test('re-importing the same file with duplicate straight sets stays '
        'idempotent', () async {
      const csv =
          '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
''';
      await storage.importFromCsvText(csv);
      final secondImportCount = await storage.importFromCsvText(csv);
      expect(secondImportCount, 0);
      expect(await storage.count(), 3);
    });

    test(
      'preserves the CSV row order for same-day sets across exercises',
      () async {
        const csv =
            '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,
2026-01-15,Bench Press,Chest,135.0,lbs,7,,,,
2026-01-15,Overhead Press,Shoulders,65.0,lbs,10,,,,
2026-01-15,Overhead Press,Shoulders,65.0,lbs,9,,,,
2026-01-15,Bench Press,Chest,135.0,lbs,6,,,,
''';
        await storage.importFromCsvText(csv);
        final loaded = await storage.loadAll();
        expect(loaded.map((s) => '${s.exercise}:${s.reps}').toList(), [
          'Bench Press:8',
          'Bench Press:7',
          'Overhead Press:10',
          'Overhead Press:9',
          'Bench Press:6',
        ]);
      },
    );

    test('returns 0 for a header-only CSV', () async {
      const headerOnly =
          'Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment\n';
      expect(await storage.importFromCsvText(headerOnly), 0);
    });

    test(
      'skips rows where weight, reps, distance, and duration are all absent',
      () async {
        const emptyRow =
            '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Mystery,Core,0,lbs,0,,,,"no data"
''';
        expect(await storage.importFromCsvText(emptyRow), 0);
      },
    );

    test('parses comment correctly', () async {
      final loaded = await storage
          .importFromCsvText(validCsv)
          .then((_) => storage.loadAll());
      final bench = loaded.firstWhere((s) => s.exercise == 'Bench Press');
      expect(bench.comment, 'good session');
    });

    test('handles quoted fields that contain commas', () async {
      const csv =
          '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,"form good, felt strong"
''';
      await storage.importFromCsvText(csv);
      final loaded = await storage.loadAll();
      expect(loaded.first.comment, 'form good, felt strong');
    });

    test('handles escaped double-quotes inside a field', () async {
      const csv =
          '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
2026-01-15,Bench Press,Chest,135.0,lbs,8,,,,"felt ""great"" today"
''';
      await storage.importFromCsvText(csv);
      final loaded = await storage.loadAll();
      expect(loaded.first.comment, 'felt "great" today');
    });

    test('imports cardio rows with distance and duration', () async {
      const csv =
          '''Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment
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

    test(
      'exercises with no entry are absent (not defaulted by storage)',
      () async {
        await storage.saveTrainingModes({'Squat': 'strength'});
        final loaded = await storage.loadTrainingModes();
        expect(loaded.containsKey('Bench Press'), isFalse);
      },
    );
  });

  group('deleteSet', () {
    test('removes the matching set from the database', () async {
      final set = strengthSet();
      await storage.appendSets([set]);
      expect(await storage.count(), 1);
      await storage.deleteSet(set);
      expect(await storage.count(), 0);
    });

    test('deletes only the targeted set, leaving others intact', () async {
      final a = strengthSet(date: DateTime(2026, 1, 1));
      final b = strengthSet(date: DateTime(2026, 1, 2), weight: 140.0);
      await storage.appendSets([a, b]);
      await storage.deleteSet(a);
      final remaining = await storage.loadAll();
      expect(remaining.length, 1);
      expect(remaining.first.weight, 140.0);
    });

    test('no-op when the set is not in the database', () async {
      await storage.deleteSet(strengthSet());
      expect(await storage.count(), 0);
    });
  });

  group('updateSet', () {
    test('replaces old set values with updated values', () async {
      final original = strengthSet();
      await storage.appendSets([original]);
      final updated = strengthSet(weight: 145.0, reps: 6);
      await storage.updateSet(original, updated);
      final all = await storage.loadAll();
      expect(all.length, 1);
      expect(all.first.weight, 145.0);
      expect(all.first.reps, 6);
    });

    test('count stays the same after update', () async {
      final original = strengthSet();
      await storage.appendSets([original]);
      await storage.updateSet(original, strengthSet(weight: 150.0));
      expect(await storage.count(), 1);
    });
  });

  group('loadProgressionAlgorithms', () {
    test('returns empty map when nothing is saved', () async {
      expect(await storage.loadProgressionAlgorithms(), isEmpty);
    });
  });

  group('saveProgressionAlgorithms / loadProgressionAlgorithms round-trip', () {
    test('persists and restores algorithm assignments', () async {
      await storage.saveProgressionAlgorithms({
        'Bench Press': 'standard',
        'Squat': 'plateauBreaker',
      });
      final loaded = await storage.loadProgressionAlgorithms();
      expect(loaded['Bench Press'], 'standard');
      expect(loaded['Squat'], 'plateauBreaker');
    });

    test('overwrites previous assignments on re-save', () async {
      await storage.saveProgressionAlgorithms({'Bench Press': 'standard'});
      await storage.saveProgressionAlgorithms({
        'Bench Press': 'plateauBreaker',
      });
      final loaded = await storage.loadProgressionAlgorithms();
      expect(loaded['Bench Press'], 'plateauBreaker');
    });
  });

  group('loadPlateauBreakerCycleStart', () {
    test('returns empty map when nothing is saved', () async {
      expect(await storage.loadPlateauBreakerCycleStart(), isEmpty);
    });
  });

  group(
    'savePlateauBreakerCycleStart / loadPlateauBreakerCycleStart round-trip',
    () {
      test('persists and restores per-exercise baselines', () async {
        await storage.savePlateauBreakerCycleStart({
          'Bench Press': 4,
          'Squat': 0,
        });
        final loaded = await storage.loadPlateauBreakerCycleStart();
        expect(loaded['Bench Press'], 4);
        expect(loaded['Squat'], 0);
      });

      test('overwrites previous baselines on re-save', () async {
        await storage.savePlateauBreakerCycleStart({'Bench Press': 4});
        await storage.savePlateauBreakerCycleStart({'Bench Press': 9});
        final loaded = await storage.loadPlateauBreakerCycleStart();
        expect(loaded['Bench Press'], 9);
      });
    },
  );

  group('loadDayMetadata', () {
    test('returns empty map when nothing is saved', () async {
      expect(await storage.loadDayMetadata(), isEmpty);
    });
  });

  group('saveDayMetadata / loadDayMetadata round-trip', () {
    test('persists and restores day metadata keyed by date', () async {
      await storage.saveDayMetadata({
        '2026-01-15': {
          'comment': 'great session',
          'startTime': '09:00',
          'endTime': '10:00',
        },
      });
      final loaded = await storage.loadDayMetadata();
      expect(loaded['2026-01-15']?['comment'], 'great session');
      expect(loaded['2026-01-15']?['startTime'], '09:00');
      expect(loaded['2026-01-15']?['endTime'], '10:00');
    });

    test('overwrites previous metadata on re-save', () async {
      await storage.saveDayMetadata({
        '2026-01-15': {'comment': 'first'},
      });
      await storage.saveDayMetadata({
        '2026-01-15': {'comment': 'second'},
      });
      final loaded = await storage.loadDayMetadata();
      expect(loaded['2026-01-15']?['comment'], 'second');
    });
  });

  group('body measurements', () {
    test('loadBodyMeasurements returns empty list initially', () async {
      expect(await storage.loadBodyMeasurements(), isEmpty);
    });

    test('addBodyMeasurement persists and returns an assigned id', () async {
      final id = await storage.addBodyMeasurement(
        BodyMeasurement(
          date: DateTime(2026, 3, 1),
          type: BodyMeasurementType.weight,
          value: 180.0,
        ),
      );
      expect(id, greaterThan(0));
      final loaded = await storage.loadBodyMeasurements();
      expect(loaded.length, 1);
      expect(loaded.first.id, id);
      expect(loaded.first.value, 180.0);
      expect(loaded.first.type, BodyMeasurementType.weight);
    });

    test('addBodyMeasurement round-trips a body fat reading', () async {
      await storage.addBodyMeasurement(
        BodyMeasurement(
          date: DateTime(2026, 3, 1),
          type: BodyMeasurementType.bodyFat,
          value: 18.5,
        ),
      );
      final loaded = await storage.loadBodyMeasurements();
      expect(loaded.first.type, BodyMeasurementType.bodyFat);
      expect(loaded.first.value, 18.5);
    });

    test('deleteBodyMeasurement removes only the targeted reading', () async {
      final keepId = await storage.addBodyMeasurement(
        BodyMeasurement(
          date: DateTime(2026, 3, 1),
          type: BodyMeasurementType.weight,
          value: 180.0,
        ),
      );
      final removeId = await storage.addBodyMeasurement(
        BodyMeasurement(
          date: DateTime(2026, 3, 2),
          type: BodyMeasurementType.weight,
          value: 181.0,
        ),
      );
      await storage.deleteBodyMeasurement(removeId);
      final loaded = await storage.loadBodyMeasurements();
      expect(loaded.length, 1);
      expect(loaded.first.id, keepId);
    });
  });

  group('migration from SharedPreferences', () {
    test(
      'migrates workout_sets_v1 JSON into SQLite on first loadAll',
      () async {
        final json = jsonEncode([
          {
            'date': '2026-01-10T10:00:00.000',
            'exercise': 'Squat',
            'category': 'Legs',
            'weight': 200.0,
            'reps': 5,
            'comment': '',
          },
        ]);
        SharedPreferences.setMockInitialValues({'workout_sets_v1': json});
        final migrated = LocalStorageService(dbPath: inMemoryDatabasePath);
        addTearDown(migrated.close);
        final sets = await migrated.loadAll();
        expect(sets.length, 1);
        expect(sets.first.exercise, 'Squat');
        expect(sets.first.weight, 200.0);
      },
    );

    test('migration does not re-import on second loadAll', () async {
      final json = jsonEncode([
        {
          'date': '2026-01-10T10:00:00.000',
          'exercise': 'Squat',
          'category': 'Legs',
          'weight': 200.0,
          'reps': 5,
          'comment': '',
        },
      ]);
      SharedPreferences.setMockInitialValues({'workout_sets_v1': json});
      final migrated = LocalStorageService(dbPath: inMemoryDatabasePath);
      addTearDown(migrated.close);
      await migrated.loadAll();
      await migrated.loadAll();
      expect(await migrated.count(), 1);
    });
  });
}
