import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exercise_analyzer/models/workout_set.dart';

/// Persists all local workout data using [SharedPreferences].
///
/// Responsible for three things:
/// 1. Reading and writing [WorkoutSet] entries (key `workout_sets_v1`).
/// 2. Importing FitNotes-compatible CSV exports with duplicate detection.
/// 3. Reading and writing per-exercise [TrainingMode] preferences (key `training_modes_v1`).
class LocalStorageService {
  static const _setsKey = 'workout_sets_v1';
  static const _modesKey = 'training_modes_v1';

  /// Loads all stored sets. Returns an empty list if nothing has been saved yet.
  Future<List<WorkoutSet>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_setsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Overwrites the entire set list in storage.
  Future<void> saveAll(List<WorkoutSet> sets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _setsKey, jsonEncode(sets.map((s) => s.toJson()).toList()));
  }

  /// Appends [newSets] to the existing stored list.
  Future<void> appendSets(List<WorkoutSet> newSets) async {
    final existing = await loadAll();
    await saveAll([...existing, ...newSets]);
  }

  Future<int> count() async => (await loadAll()).length;

  /// Removes all stored sets. Cannot be undone.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_setsKey);
  }

  /// Returns all stored sets encoded as a FitNotes-compatible CSV byte array,
  /// ready to POST to the `/train` endpoint for cloud model retraining.
  Future<Uint8List> exportAsCsvBytes() async {
    final sets = await loadAll();
    const header =
        'Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment';
    final rows = sets.map((s) => s.toCsvRow()).join('\n');
    return const Utf8Encoder().convert('$header\n$rows\n');
  }

  /// Parses a FitNotes CSV export and merges only new rows into local storage.
  ///
  /// Duplicate detection uses a fingerprint of date (day granularity) plus all
  /// data fields, so re-importing the same file is safe.
  /// Returns the number of new sets added.
  Future<int> importFromCsvText(String csvText) async {
    final lines = csvText.replaceAll('\r\n', '\n').split('\n');
    if (lines.length < 2) return 0;

    final existing = await loadAll();
    final seen = existing.map(_fingerprint).toSet();

    final newSets = <WorkoutSet>[];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      try {
        final p = _parseCsvLine(line);
        if (p.length < 6) continue;

        // FitNotes columns: Date, Exercise, Category, Weight, WeightUnit,
        //                   Reps, Distance, DistanceUnit, Time, Comment
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

        final set = WorkoutSet(
          date: DateTime.parse(p[0].trim()),
          exercise: p[1].trim(),
          category: p[2].trim(),
          weight: weight,
          reps: reps,
          distance: distance,
          distanceUnit: distanceUnit,
          duration: duration,
          comment: comment,
        );

        if (seen.add(_fingerprint(set))) {
          newSets.add(set);
        }
      } catch (_) {
        continue;
      }
    }
    if (newSets.isNotEmpty) await saveAll([...existing, ...newSets]);
    return newSets.length;
  }

  /// Loads the saved training mode for each exercise.
  ///
  /// Returns a map of exercise name → `"hypertrophy"` or `"strength"`.
  /// Exercises that have never been assigned a mode are absent from the map
  /// and default to hypertrophy in the view model.
  Future<Map<String, String>> loadTrainingModes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modesKey);
    if (raw == null || raw.isEmpty) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }

  /// Persists the training mode map returned by [loadTrainingModes].
  Future<void> saveTrainingModes(Map<String, String> modes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modesKey, jsonEncode(modes));
  }

  /// Day-level fingerprint for duplicate detection.
  ///
  /// FitNotes exports dates without time, so millisecond precision would
  /// cause every reimport to look like new data.
  static String _fingerprint(WorkoutSet s) {
    final d = s.date;
    final day =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '$day|${s.exercise}|${s.category}|${s.weight}|${s.reps}'
        '|${s.distance}|${s.distanceUnit}|${s.duration}|${s.comment}';
  }

  /// Splits a single CSV line into fields, correctly handling quoted fields
  /// that may contain commas or escaped double-quotes.
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
