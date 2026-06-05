import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:repiq/models/recommendation_models.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/analytics_service.dart';
import 'package:repiq/services/api_service.dart';
import 'package:repiq/services/local_recommendation_engine.dart';
import 'package:repiq/services/local_storage_service.dart';
import 'package:repiq/services/notification_service.dart';

export '../models/recommendation_models.dart' show TrainingMode;

// ── Isolate helpers ───────────────────────────────────────────────────────────

/// Passed to the recommendation isolate — only carries the target exercise's
/// sets so the serialization cost stays proportional to that exercise, not the
/// full history.
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

// ── Domain types ─────────────────────────────────────────────────────────────

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

  /// Cloud XGBoost recommendation — non-null for premium users who have trained
  /// a model. Overwrites [recommendation] in the UI when available.
  Recommendation? cloudRecommendation;

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

// ── ViewModel ─────────────────────────────────────────────────────────────────

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

  /// Cached result of grouping [history] by date — rebuilt only when history
  /// changes, not on every widget rebuild.
  Map<String, List<WorkoutSet>>? _historyByDateCache;

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
    _saveTrainingModes();
    _applyRec(session[index]);
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

  /// Consecutive calendar days with at least one set logged, ending today or
  /// yesterday (yesterday counts so a streak isn't broken before the gym opens).
  int get currentStreak {
    if (history.isEmpty) return 0;
    final today = DateTime.now();
    final loggedDays =
        history.map((s) => _fmtDate(s.date)).toSet();

    var check = DateTime(today.year, today.month, today.day);
    if (!loggedDays.contains(_fmtDate(check))) {
      check = check.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (loggedDays.contains(_fmtDate(check))) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// History grouped by date string (`"YYYY-MM-DD"`), sorted newest-first.
  /// Result is cached and only rebuilt when history actually changes.
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
    await _loadHistory();
    await _loadTrainingModes();
    _rebuildDict();
    _loadTodaySession();
    isDictLoading = false;
    notifyListeners();
    // Fire-and-forget: pull any sets from Firestore that are missing locally.
    _syncFromFirestore();
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

  /// Kicks off recommendation computation in a background isolate, then chains
  /// a cloud XGBoost attempt for premium users.
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
        ex.recommendation = rec;
        notifyListeners();
        _tryCloudRec(ex);
      }).catchError((_) {
        ex.recError = 'Could not compute recommendation.';
        notifyListeners();
      });
    } else {
      ex.lastSessionSummary = _lastSessionSummary(ex.exercise, ex.category);
    }
  }

  /// Attempts to fetch a cloud XGBoost recommendation. Silently no-ops on
  /// 403 (free tier) and 404 (model not trained yet).
  void _tryCloudRec(SessionExercise ex) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final cloud = await _api.getRecommendation(
          ex.exercise, ex.category, authToken: token);
      if (cloud != null) {
        ex.cloudRecommendation = cloud;
        notifyListeners();
      }
    } catch (_) {}
  }

  String _lastSessionSummary(String exercise, String category) {
    final sets = history
        .where((s) => s.exercise == exercise)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (sets.isEmpty) return '';
    final lastDate = _fmtDate(sets.first.date);
    final lastSets =
        sets.where((s) => _fmtDate(s.date) == lastDate).toList();
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

  /// Adds [exercise] to the current session if it isn't already present,
  /// and kicks off its recommendation computation.
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
    if (session.length == 1) AnalyticsService.logSessionStarted();
    AnalyticsService.logExerciseAdded(exercise);
    notifyListeners();
  }

  /// Appends [set] to the session, persists it, syncs to Firestore, and
  /// reschedules the 3-day workout reminder notification.
  void logSet(int exerciseIndex, WorkoutSet set) {
    session[exerciseIndex].sets.add(set);
    history.insert(0, set);
    _invalidateHistoryCache();
    localSetCount++;
    notifyListeners();
    _storage.appendSets([set]);
    _syncSetToFirestore(set);
    AnalyticsService.logSetLogged(set.exercise);
    NotificationService.scheduleWorkoutReminder();
    _maybeLogStreakMilestone();
  }

  void _maybeLogStreakMilestone() {
    final s = currentStreak;
    if (s == 3 || s == 7 || s == 14 || s == 30) {
      AnalyticsService.logStreakMilestone(s);
    }
  }

  /// Removes the set at [setIndex] from the session and from storage.
  void removeSet(int exerciseIndex, int setIndex) {
    final set = session[exerciseIndex].sets.removeAt(setIndex);
    history.removeWhere((s) =>
        s.date.millisecondsSinceEpoch == set.date.millisecondsSinceEpoch &&
        s.exercise == set.exercise);
    _invalidateHistoryCache();
    localSetCount--;
    notifyListeners();
    _storage.deleteSet(set);
    _syncDeleteFromFirestore(set);
  }

  /// Replaces the set at [setIndex] with [updated], persists, and re-syncs.
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
    _syncDeleteFromFirestore(old);
    _syncSetToFirestore(updated);
  }

  /// Removes an entire exercise and all its sets from the session and storage.
  void removeExercise(int index) {
    final sets = List<WorkoutSet>.from(session[index].sets);
    session.removeAt(index);
    notifyListeners();
    for (final s in sets) {
      _storage.deleteSet(s);
      _syncDeleteFromFirestore(s);
    }
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
      AnalyticsService.logCsvImported(count);
      lastActionMessage = 'Imported $count sets from CSV.';
    } catch (e) {
      lastActionMessage = 'Import failed: $e';
    } finally {
      isImporting = false;
      notifyListeners();
    }
  }

  /// Exports local data as CSV and POSTs to the cloud `/train` endpoint.
  Future<void> trainOnLocalData() async {
    isTraining = true;
    lastActionMessage = null;
    notifyListeners();
    try {
      final bytes = await _storage.exportAsCsvBytes();
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      await _api.trainFromCsvBytes(bytes, authToken: token);
      AnalyticsService.logCloudRetrain();
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

  // ── Firestore sync ────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>>? _setsCollection() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sets');
  }

  /// Pull any sets stored in Firestore that are not yet in the local DB.
  /// Fire-and-forget — failure is silently ignored so offline use is unaffected.
  void _syncFromFirestore() async {
    try {
      final col = _setsCollection();
      if (col == null) return;
      final snap = await col.get();
      if (snap.docs.isEmpty) return;
      final remoteSets =
          snap.docs.map((d) => WorkoutSet.fromJson(d.data())).toList();
      await _storage.appendSets(remoteSets);
      // Reload only if new sets were actually added.
      final newCount = await _storage.count();
      if (newCount != localSetCount) {
        await _loadHistory();
        _rebuildDict();
        _loadTodaySession();
        notifyListeners();
      }
    } catch (_) {}
  }

  void _syncSetToFirestore(WorkoutSet set) async {
    try {
      final col = _setsCollection();
      if (col == null) return;
      final id = LocalStorageService.fingerprintFor(set);
      await col.doc(id).set(set.toJson());
    } catch (_) {}
  }

  void _syncDeleteFromFirestore(WorkoutSet set) async {
    try {
      final col = _setsCollection();
      if (col == null) return;
      final id = LocalStorageService.fingerprintFor(set);
      await col.doc(id).delete();
    } catch (_) {}
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
