import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:repiq/models/workout_set.dart';

/// Persists all local workout data in a SQLite database.
///
/// Sets are keyed by a deterministic [fingerprintFor] so duplicate imports are
/// silently ignored. Training mode preferences stay in SharedPreferences (they
/// are a tiny map and don't benefit from SQL).
///
/// Migration: on the first open after upgrading from the SharedPreferences-only
/// version, all existing sets are moved into SQLite and the old prefs key is
/// removed.
class LocalStorageService {
  static const _modesKey = 'training_modes_v1';
  static const _migratedKey = 'sqflite_migrated_v1';

  LocalStorageService({String? dbPath}) : _dbPath = dbPath;
  final String? _dbPath;

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    final path = _dbPath ?? join(await getDatabasesPath(), 'repiq.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE sets (
          fingerprint   TEXT PRIMARY KEY,
          date_iso      TEXT NOT NULL,
          exercise      TEXT NOT NULL,
          category      TEXT NOT NULL,
          weight        REAL NOT NULL DEFAULT 0.0,
          reps          INTEGER NOT NULL DEFAULT 0,
          distance      REAL,
          distance_unit TEXT,
          duration      TEXT,
          comment       TEXT NOT NULL DEFAULT ""
        )
      '''),
    );
  }

  /// One-time migration from the SharedPreferences JSON blob.
  Future<void> _migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) == true) return;

    final raw = prefs.getString('workout_sets_v1');
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List<dynamic>;
      final sets = list
          .map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
          .toList();
      if (sets.isNotEmpty) await appendSets(sets);
      await prefs.remove('workout_sets_v1');
    }
    await prefs.setBool(_migratedKey, true);
  }

  Future<List<WorkoutSet>> loadAll() async {
    await _migrateIfNeeded();
    final db = await _database;
    final rows = await db.query('sets', orderBy: 'date_iso ASC');
    return rows.map(_rowToSet).toList();
  }

  /// Inserts new sets, silently skipping any duplicates.
  Future<void> appendSets(List<WorkoutSet> newSets) async {
    final db = await _database;
    final batch = db.batch();
    for (final s in newSets) {
      batch.insert('sets', _setToRow(s),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM sets');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> clear() async {
    final db = await _database;
    await db.delete('sets');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// O(1) delete using the fingerprint primary key.
  Future<void> deleteSet(WorkoutSet target) async {
    final db = await _database;
    await db.delete('sets',
        where: 'fingerprint = ?', whereArgs: [fingerprintFor(target)]);
  }

  /// O(1) update: delete old row by fingerprint, insert updated row.
  Future<void> updateSet(WorkoutSet old, WorkoutSet updated) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('sets',
          where: 'fingerprint = ?', whereArgs: [fingerprintFor(old)]);
      await txn.insert('sets', _setToRow(updated),
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<Uint8List> exportAsCsvBytes() async {
    final sets = await loadAll();
    const header =
        'Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment';
    final rows = sets.map((s) => s.toCsvRow()).join('\n');
    return const Utf8Encoder().convert('$header\n$rows\n');
  }

  /// Parses a FitNotes CSV and inserts only rows not already in the database.
  /// Returns the number of new sets added.
  Future<int> importFromCsvText(String csvText) async {
    final lines = csvText.replaceAll('\r\n', '\n').split('\n');
    if (lines.length < 2) return 0;

    final newSets = <WorkoutSet>[];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      try {
        final p = _parseCsvLine(line);
        if (p.length < 6) continue;

        final weight = double.tryParse(p[3].trim()) ?? 0.0;
        final reps = int.tryParse(p[5].trim()) ?? 0;
        final distance =
            p.length > 6 ? double.tryParse(p[6].trim()) : null;
        final distanceUnit =
            (p.length > 7 && p[7].trim().isNotEmpty) ? p[7].trim() : null;
        final duration =
            (p.length > 8 && p[8].trim().isNotEmpty) ? p[8].trim() : null;
        final comment = p.length > 9 ? p[9].trim() : '';

        final hasStrength = weight > 0 || reps > 0;
        final hasCardio = distance != null && distance > 0;
        final hasDuration = duration != null;
        if (!hasStrength && !hasCardio && !hasDuration) continue;

        newSets.add(WorkoutSet(
          date: DateTime.parse(p[0].trim()),
          exercise: p[1].trim(),
          category: p[2].trim(),
          weight: weight,
          reps: reps,
          distance: distance,
          distanceUnit: distanceUnit,
          duration: duration,
          comment: comment,
        ));
      } catch (_) {
        continue;
      }
    }
    if (newSets.isEmpty) return 0;

    final before = await count();
    await appendSets(newSets);
    final after = await count();
    return after - before;
  }

  Future<Map<String, String>> loadTrainingModes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modesKey);
    if (raw == null || raw.isEmpty) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }

  Future<void> saveTrainingModes(Map<String, String> modes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modesKey, jsonEncode(modes));
  }

  /// Day-level fingerprint used as the SQLite PRIMARY KEY and Firestore doc ID.
  /// Stable across CSV re-imports; intentionally day-level so duplicate imports
  /// are idempotent even when the original timestamp is unavailable.
  static String fingerprintFor(WorkoutSet s) {
    final d = s.date;
    final day =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '$day|${s.exercise}|${s.category}|${s.weight}|${s.reps}'
        '|${s.distance}|${s.distanceUnit}|${s.duration}|${s.comment}';
  }

  static Map<String, dynamic> _setToRow(WorkoutSet s) => {
        'fingerprint': fingerprintFor(s),
        'date_iso': s.date.toIso8601String(),
        'exercise': s.exercise,
        'category': s.category,
        'weight': s.weight,
        'reps': s.reps,
        'distance': s.distance,
        'distance_unit': s.distanceUnit,
        'duration': s.duration,
        'comment': s.comment,
      };

  static WorkoutSet _rowToSet(Map<String, dynamic> row) => WorkoutSet(
        date: DateTime.parse(row['date_iso'] as String),
        exercise: row['exercise'] as String,
        category: row['category'] as String,
        weight: (row['weight'] as num).toDouble(),
        reps: row['reps'] as int,
        distance: (row['distance'] as num?)?.toDouble(),
        distanceUnit: row['distance_unit'] as String?,
        duration: row['duration'] as String?,
        comment: row['comment'] as String? ?? '',
      );

  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    var inQuotes = false;
    final buf = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ',' && !inQuotes) {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    result.add(buf.toString());
    return result;
  }
}
