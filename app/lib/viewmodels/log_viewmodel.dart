import 'package:flutter/material.dart';
import '../models/recommendation_models.dart';
import '../models/workout_set.dart';
import '../services/api_service.dart';
import '../services/local_recommendation_engine.dart';
import '../services/local_storage_service.dart';

enum ExerciseType { strength, cardio, passive }

ExerciseType exerciseTypeOf(String category) {
  if (category == 'Cardio') return ExerciseType.cardio;
  if (category == 'Passive') return ExerciseType.passive;
  return ExerciseType.strength;
}

class SessionExercise {
  final String exercise;
  final String category;
  Recommendation? recommendation;
  String? recError;
  String? lastSessionSummary;
  final List<WorkoutSet> sets = [];

  SessionExercise({required this.exercise, required this.category});
}

class LogViewModel extends ChangeNotifier {
  final _api = ApiService();
  final _storage = LocalStorageService();

  Map<String, List<String>> exerciseDict = {};
  bool isDictLoading = true;

  final List<SessionExercise> session = [];

  List<WorkoutSet> history = [];
  bool isHistoryLoading = false;

  bool isTraining = false;
  bool isImporting = false;
  String? lastActionMessage;
  int localSetCount = 0;

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

  // All categories with presets are always shown, even with no history.
  static final _alwaysCategories = _presetExercises.keys.toSet();

  LogViewModel() {
    _initialize();
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
    _rebuildDict();
    _loadTodaySession();
    isDictLoading = false;
    notifyListeners();
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
        final ex = SessionExercise(exercise: s.exercise, category: s.category);
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

  void addExercise(String category, String exercise) {
    if (session.any(
        (e) => e.exercise == exercise && e.category == category)) {
      return;
    }
    final ex = SessionExercise(exercise: exercise, category: category);
    _applyRec(ex);
    session.add(ex);
    notifyListeners();
  }

  void logSet(int exerciseIndex, WorkoutSet set) {
    session[exerciseIndex].sets.add(set);
    history.insert(0, set);
    localSetCount++;
    notifyListeners();
    _storage.appendSets([set]);
  }

  void removeSet(int exerciseIndex, int setIndex) {
    final set = session[exerciseIndex].sets.removeAt(setIndex);
    localSetCount--;
    notifyListeners();
    _deleteSetFromStorage(set);
  }

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

  Future<void> trainOnLocalData() async {
    isTraining = true;
    lastActionMessage = null;
    notifyListeners();
    try {
      final bytes = await _storage.exportAsCsvBytes();
      await _api.trainFromCsvBytes(bytes);
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
