import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:repiq/models/recommendation_models.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/api_service.dart';
import 'package:repiq/services/local_recommendation_engine.dart';
import 'package:repiq/services/local_storage_service.dart';

export '../models/recommendation_models.dart' show TrainingMode;

/// Broad category of an exercise, used to route UI and recommendation logic.
enum ExerciseType { strength, cardio, passive }

/// Maps a FitNotes category string to an [ExerciseType].
ExerciseType exerciseTypeOf(String category) {
  if (category == 'Cardio') return ExerciseType.cardio;
  if (category == 'Passive') return ExerciseType.passive;
  return ExerciseType.strength;
}

/// One exercise added to the current session, along with its logged sets and
/// the most recent recommendation.
class SessionExercise {
  final String exercise;
  final String category;

  /// Whether this exercise is being trained for hypertrophy or absolute strength.
  /// Persists across sessions via [LogViewModel].
  TrainingMode trainingMode;

  /// The AI-generated recommendation for this session. Null until computed,
  /// or for non-strength exercises.
  Recommendation? recommendation;

  /// Non-null when recommendation computation failed.
  String? recError;

  /// Human-readable summary of the last cardio or passive session, shown
  /// instead of a strength recommendation for those exercise types.
  String? lastSessionSummary;

  final List<WorkoutSet> sets = [];

  SessionExercise({
    required this.exercise,
    required this.category,
    this.trainingMode = TrainingMode.hypertrophy,
  });
}

/// Central state manager for the app (Provider / [ChangeNotifier]).
///
/// Owns:
/// - The full [history] of logged sets (loaded from [LocalStorageService])
/// - The current workout [session] (today's exercises and their logged sets)
/// - The [exerciseDict] used to populate category/exercise pickers
/// - Per-exercise [TrainingMode] preferences
/// - Loading and error state for import and cloud training operations
class LogViewModel extends ChangeNotifier {
  final _api = ApiService();
  final _storage = LocalStorageService();

  /// Category → sorted exercise name list, built from history + presets.
  Map<String, List<String>> exerciseDict = {};
  bool isDictLoading = true;

  /// Exercises added to today's session, in the order they were added.
  final List<SessionExercise> session = [];

  /// Full workout history, sorted newest-first.
  List<WorkoutSet> history = [];
  bool isHistoryLoading = false;

  bool isTraining = false;
  bool isImporting = false;

  /// Result message from the last import or cloud training action.
  String? lastActionMessage;

  /// Total number of sets currently stored on-device.
  int localSetCount = 0;

  Map<String, TrainingMode> _trainingModes = {};

  /// Built-in exercise list shown even before the user has any history.
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

  LogViewModel() {
    _initialize();
  }

  /// Returns the saved [TrainingMode] for [exercise], defaulting to hypertrophy.
  TrainingMode trainingModeFor(String exercise) =>
      _trainingModes[exercise] ?? TrainingMode.hypertrophy;

  /// Updates the training mode for the exercise at [index], persists it, and
  /// immediately recomputes the recommendation.
  void setTrainingMode(int index, TrainingMode mode) {
    session[index].trainingMode = mode;
    _trainingModes[session[index].exercise] = mode;
    _applyRec(session[index]);
    _saveTrainingModes();
    notifyListeners();
  }

  /// All categories, combining history and presets, sorted alphabetically.
  List<String> get allCategories {
    final cats = <String>{...exerciseDict.keys, ..._alwaysCategories};
    return cats.toList()..sort();
  }

  /// Sorted exercise names for [category], merging history and presets.
  List<String> exercisesFor(String category) {
    final fromHistory = exerciseDict[category] ?? <String>[];
    final presets = _presetExercises[category] ?? <String>[];
    return <String>{...fromHistory, ...presets}.toList()..sort();
  }

  /// History grouped by date string (`"YYYY-MM-DD"`), sorted newest-first.
  Map<String, List<WorkoutSet>> get historyByDate {
    final grouped = <String, List<WorkoutSet>>{};
    for (final s in history) {
      grouped.putIfAbsent(_fmtDate(s.date), () => []).add(s);
    }
    return grouped;
  }

  Future<void> _initialize() async {
    isDictLoading = true;
    notifyListeners();
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
      (k, v) => MapEntry(k, v == 'strength' ? TrainingMode.strength : TrainingMode.hypertrophy),
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

  /// Restores any exercises already logged today so a mid-session app restart
  /// doesn't lose the current session.
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
  }

  void _applyRec(SessionExercise ex) {
    if (exerciseTypeOf(ex.category) == ExerciseType.strength) {
      try {
        ex.recommendation = LocalRecommendationEngine.recommend(
          exercise: ex.exercise,
          category: ex.category,
          allHistory: history,
          mode: ex.trainingMode,
        );
      } catch (_) {
        ex.recError = 'Could not compute recommendation.';
      }
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
          lastSets.fold(0.0, (sum, s) => sum + (s.distance ?? 0.0));
      final unit = lastSets.first.distanceUnit ?? 'mi';
      return '${lastSets.length} lap${lastSets.length == 1 ? '' : 's'} · '
          '${totalDist.toStringAsFixed(2)} $unit';
    }
    final dur = lastSets.first.duration;
    return dur != null ? 'Last session: $dur' : '';
  }

  /// Adds [exercise] to the current session if it isn't already present,
  /// and immediately computes its recommendation.
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
    notifyListeners();
  }

  /// Appends [set] to the session and persists it immediately.
  void logSet(int exerciseIndex, WorkoutSet set) {
    session[exerciseIndex].sets.add(set);
    history.insert(0, set);
    localSetCount++;
    notifyListeners();
    _storage.appendSets([set]);
  }

  /// Removes the set at [setIndex] from the session and from storage.
  void removeSet(int exerciseIndex, int setIndex) {
    final set = session[exerciseIndex].sets.removeAt(setIndex);
    localSetCount--;
    notifyListeners();
    _deleteSetFromStorage(set);
  }

  /// Replaces the set at [setIndex] with [updated], preserving its original
  /// timestamp, and recomputes the recommendation with the new data.
  void updateSet(int exerciseIndex, int setIndex, WorkoutSet updated) {
    final old = session[exerciseIndex].sets[setIndex];
    session[exerciseIndex].sets[setIndex] = updated;
    final hi = history.indexWhere((s) =>
        s.date.millisecondsSinceEpoch == old.date.millisecondsSinceEpoch &&
        s.exercise == old.exercise);
    if (hi != -1) history[hi] = updated;
    _applyRec(session[exerciseIndex]);
    notifyListeners();
    _persistUpdate(old, updated);
  }

  Future<void> _persistUpdate(WorkoutSet old, WorkoutSet updated) async {
    final all = await _storage.loadAll();
    final i = all.indexWhere((s) =>
        s.date.millisecondsSinceEpoch == old.date.millisecondsSinceEpoch &&
        s.exercise == old.exercise);
    if (i != -1) all[i] = updated;
    await _storage.saveAll(all);
  }

  /// Removes an entire exercise and all its sets from the session and storage.
  void removeExercise(int index) {
    final sets = List<WorkoutSet>.from(session[index].sets);
    session.removeAt(index);
    notifyListeners();
    for (final s in sets) {
      _deleteSetFromStorage(s);
    }
  }

  Future<void> _deleteSetFromStorage(WorkoutSet target) async {
    final all = await _storage.loadAll();
    all.removeWhere((s) =>
        s.date.millisecondsSinceEpoch == target.date.millisecondsSinceEpoch &&
        s.exercise == target.exercise);
    await _storage.saveAll(all);
    history = all;
    history.sort((a, b) => b.date.compareTo(a.date));
    localSetCount = history.length;
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    isHistoryLoading = true;
    notifyListeners();
    try {
      history = await _storage.loadAll();
      history.sort((a, b) => b.date.compareTo(a.date));
      localSetCount = history.length;
    } catch (e) {
      debugPrint('History load error: $e');
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
  }

  /// Parses [csvText] as a FitNotes export and merges new rows into storage.
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
    } catch (e) {
      lastActionMessage = 'Import failed: $e';
    } finally {
      isImporting = false;
      notifyListeners();
    }
  }

  /// Exports local data as CSV and POSTs it to the cloud `/train` endpoint
  /// to retrain the XGBoost model. The on-device engine is unaffected.
  /// Exports local data as CSV and POSTs it to the cloud `/train` endpoint
  /// to retrain the XGBoost model. Attaches a Firebase ID token so the backend
  /// can verify the caller's identity and subscription status.
  Future<void> trainOnLocalData() async {
    isTraining = true;
    lastActionMessage = null;
    notifyListeners();
    try {
      final bytes = await _storage.exportAsCsvBytes();
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      await _api.trainFromCsvBytes(bytes, authToken: token);
      lastActionMessage =
          'Cloud model retrained on $localSetCount sets. '
          'Local recommendations already use all your data automatically.';
    } catch (e) {
      lastActionMessage = 'Training failed: $e';
    } finally {
      isTraining = false;
      notifyListeners();
    }
  }

  /// Permanently deletes all locally stored sets and clears the session.
  Future<void> clearLocalData() async {
    await _storage.clear();
    await _loadHistory();
    _rebuildDict();
    session.clear();
    notifyListeners();
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
