import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:repiq/models/recommendation_models.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/local_recommendation_engine.dart';
import 'package:repiq/services/local_storage_service.dart';
import 'package:repiq/services/notification_service.dart';

export '../models/recommendation_models.dart' show TrainingMode;

class _RecParams {
  final String exercise;
  final String category;
  final List<Map<String, dynamic>> setsJson;
  final String mode;
  const _RecParams(this.exercise, this.category, this.setsJson, this.mode);
}

Recommendation _computeRec(_RecParams p) {
  final sets = p.setsJson.map(WorkoutSet.fromJson).toList();
  return LocalRecommendationEngine.recommend(
    exercise: p.exercise,
    category: p.category,
    allHistory: sets,
    mode: p.mode == 'strength' ? TrainingMode.strength : TrainingMode.hypertrophy,
  );
}

/// Categorizes an exercise so the UI shows the right input fields and the
/// recommendation engine knows which algorithm to apply.
enum ExerciseType { strength, cardio, passive }

/// Maps a category string to [ExerciseType]. Defaults to [ExerciseType.strength]
/// for any unrecognised category.
ExerciseType exerciseTypeOf(String category) {
  if (category == 'Cardio') return ExerciseType.cardio;
  if (category == 'Passive') return ExerciseType.passive;
  return ExerciseType.strength;
}

/// One exercise entry in today's live session.
/// Holds the recommendation (computed async), current training mode, and all
/// sets logged so far today.
class SessionExercise {
  final String exercise;
  final String category;

  TrainingMode trainingMode;

  Recommendation? recommendation;

  String? recError;

  String? lastSessionSummary;

  final List<WorkoutSet> sets = [];

  SessionExercise({
    required this.exercise,
    required this.category,
    this.trainingMode = TrainingMode.hypertrophy,
  });
}

/// Central state for the log tab.
///
/// Owns today's [session] list, the full workout [history], and the exercise
/// dictionary used to populate the add-exercise dialog. All persistence goes
/// through [LocalStorageService]; recommendations are computed via
/// [LocalRecommendationEngine] in a [compute] isolate.
class LogViewModel extends ChangeNotifier with WidgetsBindingObserver {
  final _storage = LocalStorageService();

  Map<String, List<String>> exerciseDict = {};
  bool isDictLoading = true;

  final List<SessionExercise> session = [];

  List<WorkoutSet> history = [];
  bool isHistoryLoading = false;

  bool isImporting = false;
  bool isDeleting = false;

  String? lastActionMessage;

  int localSetCount = 0;

  Map<String, TrainingMode> _trainingModes = {};

  SharedPreferences? _prefs;

  Map<String, List<WorkoutSet>>? _historyByDateCache;

  static const _presetExercises = <String, List<String>>{
    'Back': [
      'Barbell Row', 'Deadlift', 'Face Pull', 'Hyperextension',
      'Lat Pulldown', 'Pull Up', 'Seated Cable Row',
      'Single Arm Dumbbell Row', 'T-Bar Row',
    ],
    'Biceps': [
      'Barbell Curl', 'Cable Curl', 'Concentration Curl',
      'Dumbbell Curl', 'EZ Bar Curl', 'Hammer Curl',
      'Incline Dumbbell Curl', 'Preacher Curl',
    ],
    'Cardio': [
      'Cycling', 'Elliptical', 'General Running', 'Jump Rope',
      'Rowing Machine', 'Stair Climber', 'Swimming',
    ],
    'Chest': [
      'Bench Press', 'Cable Fly', 'Chest Dip', 'Decline Bench Press',
      'Dumbbell Fly', 'Incline Bench Press', 'Incline Dumbbell Press',
      'Pec Deck', 'Push Up',
    ],
    'Core': [
      'Ab Wheel', 'Cable Crunch', 'Crunch', 'Hanging Leg Raise',
      'Leg Raise', 'Plank', 'Russian Twist', 'Side Plank',
    ],
    'Forearms': [
      'Barbell Wrist Curl', 'Farmer\'s Walk', 'Reverse Curl',
      'Reverse Wrist Curl',
    ],
    'Legs': [
      'Bulgarian Split Squat', 'Calf Raise', 'Glute Bridge',
      'Hack Squat', 'Leg Curl', 'Leg Extension', 'Leg Press',
      'Lunge', 'Romanian Deadlift', 'Squat',
    ],
    'Passive': [
      'Foam Rolling', 'Ice Bath', 'Sauna', 'Stretching',
    ],
    'Shoulders': [
      'Arnold Press', 'Front Raise', 'Lateral Raise',
      'Overhead Press', 'Rear Delt Fly', 'Shrug', 'Upright Row',
    ],
    'Triceps': [
      'Cable Tricep Pushdown', 'Close Grip Bench Press',
      'Diamond Push Up', 'Overhead Tricep Extension',
      'Skull Crusher', 'Tricep Dip',
    ],
  };

  static final _alwaysCategories = _presetExercises.keys.toSet();

  static const _sessionOrderKey = 'session_order_v1';
  static const _sessionOrderDateKey = 'session_order_date_v1';

  LogViewModel() {
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  TrainingMode trainingModeFor(String exercise) =>
      _trainingModes[exercise] ?? TrainingMode.hypertrophy;

  void setTrainingMode(int index, TrainingMode mode) {
    session[index].trainingMode = mode;
    _trainingModes[session[index].exercise] = mode;
    _saveTrainingModes();
    _applyRec(session[index]);
    notifyListeners();
  }

  List<String> get allCategories {
    final cats = <String>{...exerciseDict.keys, ..._alwaysCategories};
    return cats.toList()..sort();
  }

  List<String> exercisesFor(String category) {
    final fromHistory = exerciseDict[category] ?? <String>[];
    final presets = _presetExercises[category] ?? <String>[];
    return <String>{...fromHistory, ...presets}.toList()..sort();
  }

  Map<String, List<WorkoutSet>> get historyByDate {
    if (_historyByDateCache != null) return _historyByDateCache!;
    final grouped = <String, List<WorkoutSet>>{};
    for (final s in history) {
      grouped.putIfAbsent(_fmtDate(s.date), () => []).add(s);
    }
    _historyByDateCache = grouped;
    return grouped;
  }

  void _invalidateHistoryCache() => _historyByDateCache = null;

  Future<void> _initialize() async {
    isDictLoading = true;
    notifyListeners();
    _prefs = await SharedPreferences.getInstance();
    await _loadHistory();
    await _loadTrainingModes();
    _rebuildDict();
    _loadTodaySession();
    isDictLoading = false;
    notifyListeners();
  }

  Future<void> _loadTrainingModes() async {
    final raw = await _storage.loadTrainingModes();
    _trainingModes = raw.map(
      (k, v) => MapEntry(
          k, v == 'strength' ? TrainingMode.strength : TrainingMode.hypertrophy),
    );
  }

  void _saveTrainingModes() {
    _storage.saveTrainingModes(
      _trainingModes.map((k, v) => MapEntry(k, v.name)),
    );
  }

  void _rebuildDict() {
    final map = <String, Set<String>>{};
    for (final s in history) {
      map.putIfAbsent(s.category, () => {}).add(s.exercise);
    }
    exerciseDict = map.map(
      (cat, exSet) => MapEntry(cat, exSet.toList()..sort()),
    );
  }

  void _loadTodaySession() {
    session.clear();
    final today = _fmtDate(DateTime.now());
    final todaySets = history
        .where((s) => _fmtDate(s.date) == today)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    for (final s in todaySets) {
      var idx = session.indexWhere(
          (e) => e.exercise == s.exercise && e.category == s.category);
      if (idx == -1) {
        final ex = SessionExercise(
          exercise: s.exercise,
          category: s.category,
          trainingMode: trainingModeFor(s.exercise),
        );
        _applyRec(ex);
        session.add(ex);
        idx = session.length - 1;
      }
      session[idx].sets.add(s);
    }

    final prefs = _prefs;
    if (prefs != null && prefs.getString(_sessionOrderDateKey) == today) {
      final savedOrder = prefs.getStringList(_sessionOrderKey) ?? [];
      for (final entry in savedOrder) {
        final sep = entry.indexOf('|||');
        if (sep == -1) continue;
        final exercise = entry.substring(0, sep);
        final category = entry.substring(sep + 3);
        if (!session.any((e) => e.exercise == exercise && e.category == category)) {
          final ex = SessionExercise(
            exercise: exercise,
            category: category,
            trainingMode: trainingModeFor(exercise),
          );
          _applyRec(ex);
          session.add(ex);
        }
      }
      if (savedOrder.isNotEmpty) {
        session.sort((a, b) {
          final aKey = '${a.exercise}|||${a.category}';
          final bKey = '${b.exercise}|||${b.category}';
          final ai = savedOrder.indexOf(aKey);
          final bi = savedOrder.indexOf(bKey);
          if (ai == -1 && bi == -1) return 0;
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        });
      }
    }
  }

  void _saveSessionOrder() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final today = _fmtDate(DateTime.now());
    final order = session.map((e) => '${e.exercise}|||${e.category}').toList();
    await prefs.setString(_sessionOrderDateKey, today);
    await prefs.setStringList(_sessionOrderKey, order);
  }

  void _applyRec(SessionExercise ex) {
    if (exerciseTypeOf(ex.category) == ExerciseType.strength) {
      final params = _RecParams(
        ex.exercise,
        ex.category,
        history
            .where((s) => s.exercise == ex.exercise)
            .map((s) => s.toJson())
            .toList(),
        ex.trainingMode.name,
      );
      compute(_computeRec, params).then((rec) {
        if (!hasListeners) return;
        ex.recommendation = rec;
        notifyListeners();
      }).catchError((_) {
        if (!hasListeners) return;
        ex.recError = 'Could not compute recommendation.';
        notifyListeners();
      });
    } else {
      ex.lastSessionSummary = _lastSessionSummary(ex.exercise, ex.category);
    }
  }

  String _lastSessionSummary(String exercise, String category) {
    final sets = history
        .where((s) => s.exercise == exercise)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (sets.isEmpty) return '';
    final lastDate = _fmtDate(sets.first.date);
    final lastSets = sets.where((s) => _fmtDate(s.date) == lastDate).toList();
    if (exerciseTypeOf(category) == ExerciseType.cardio) {
      final totalDist =
          lastSets.fold(0.0, (acc, s) => acc + (s.distance ?? 0.0));
      final unit = lastSets.first.distanceUnit ?? 'mi';
      return '${lastSets.length} lap${lastSets.length == 1 ? '' : 's'} · '
          '${totalDist.toStringAsFixed(2)} $unit';
    }
    final dur = lastSets.first.duration;
    return dur != null ? 'Last session: $dur' : '';
  }

  void addExercise(String category, String exercise) {
    if (session.any(
        (e) => e.exercise == exercise && e.category == category)) {
      return;
    }
    final ex = SessionExercise(
      exercise: exercise,
      category: category,
      trainingMode: trainingModeFor(exercise),
    );
    _applyRec(ex);
    session.add(ex);
    _saveSessionOrder();
    notifyListeners();
  }

  void logSet(int exerciseIndex, WorkoutSet set) {
    session[exerciseIndex].sets.add(set);
    history.insert(0, set);
    _invalidateHistoryCache();
    localSetCount++;
    notifyListeners();
    _storage.appendSets([set]);
    _scheduleReminderIfNeeded();
  }

  void _scheduleReminderIfNeeded() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final today = _fmtDate(DateTime.now());
    if (prefs.getString('last_notif_day') == today) return;
    await prefs.setString('last_notif_day', today);
    NotificationService.scheduleWorkoutReminder();
  }

  void removeSet(int exerciseIndex, int setIndex) {
    final set = session[exerciseIndex].sets.removeAt(setIndex);
    history.removeWhere((s) =>
        s.date.millisecondsSinceEpoch == set.date.millisecondsSinceEpoch &&
        s.exercise == set.exercise);
    _invalidateHistoryCache();
    localSetCount--;
    notifyListeners();
    _storage.deleteSet(set);
  }

  void updateSet(int exerciseIndex, int setIndex, WorkoutSet updated) {
    final old = session[exerciseIndex].sets[setIndex];
    session[exerciseIndex].sets[setIndex] = updated;
    final hi = history.indexWhere((s) =>
        s.date.millisecondsSinceEpoch == old.date.millisecondsSinceEpoch &&
        s.exercise == old.exercise);
    if (hi != -1) history[hi] = updated;
    _invalidateHistoryCache();
    _applyRec(session[exerciseIndex]);
    notifyListeners();
    _storage.updateSet(old, updated);
  }

  void removeExercise(int index) {
    final sets = List<WorkoutSet>.from(session[index].sets);
    session.removeAt(index);
    for (final s in sets) {
      history.removeWhere((h) =>
          h.date.millisecondsSinceEpoch == s.date.millisecondsSinceEpoch &&
          h.exercise == s.exercise);
      _storage.deleteSet(s);
    }
    _invalidateHistoryCache();
    localSetCount -= sets.length;
    _saveSessionOrder();
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    isHistoryLoading = true;
    notifyListeners();
    try {
      history = await _storage.loadAll();
      history.sort((a, b) => b.date.compareTo(a.date));
      _invalidateHistoryCache();
      localSetCount = history.length;
    } catch (e) {
      debugPrint('History load error: $e');
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
  }

  Future<void> importCsvText(String csvText) async {
    isImporting = true;
    lastActionMessage = null;
    notifyListeners();
    try {
      final count = await _storage.importFromCsvText(csvText);
      await _loadHistory();
      _rebuildDict();
      _loadTodaySession();
      lastActionMessage = 'Imported $count sets from CSV.';
      if (count > 0) NotificationService.scheduleWorkoutReminder();
    } catch (e) {
      lastActionMessage = 'Import failed: $e';
    } finally {
      isImporting = false;
      notifyListeners();
    }
  }

  Future<void> clearLocalData() async {
    await _storage.clear();
    NotificationService.cancelWorkoutReminder();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.remove('last_firestore_sync_ms');
    await prefs.remove(_sessionOrderKey);
    await prefs.remove(_sessionOrderDateKey);
    await _loadHistory();
    _rebuildDict();
    session.clear();
    notifyListeners();
  }

  void dismissLastActionMessage() {
    lastActionMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
