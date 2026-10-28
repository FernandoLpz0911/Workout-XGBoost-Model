import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

WorkoutSet _set(DateTime d, {String ex = 'Bench Press', int reps = 8}) =>
    WorkoutSet(
      date: d,
      exercise: ex,
      category: 'Chest',
      weight: 135,
      reps: reps,
    );

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LogViewModel vm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'last_notif_day': LogViewModel.fmtDate(DateTime.now()),
    });
    vm = LogViewModel();
    while (vm.isDictLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    vm.history = [];
    vm.session.clear();
  });

  tearDown(() => vm.dispose());

  test('defaults to today', () {
    expect(_day(vm.selectedDate), _day(DateTime.now()));
    expect(vm.isToday, isTrue);
  });

  test('previousDay / nextDay / selectDate move selectedDate', () {
    final today = _day(DateTime.now());
    vm.previousDay();
    expect(
      _day(vm.selectedDate),
      DateTime(today.year, today.month, today.day - 1),
    );
    expect(vm.isToday, isFalse);
    vm.nextDay();
    expect(_day(vm.selectedDate), today);
    expect(vm.isToday, isTrue);
    vm.selectDate(DateTime(2026, 3, 5, 14, 30));
    expect(vm.selectedDate, DateTime(2026, 3, 5));
  });

  test('notifies listeners on date change', () {
    var n = 0;
    vm.addListener(() => n++);
    vm.previousDay();
    expect(n, 1);
  });

  test('past day session is built from history grouped by exercise', () {
    final d = DateTime(2026, 3, 5);
    vm.history = [
      _set(d.add(const Duration(hours: 11)), reps: 6),
      _set(d.add(const Duration(hours: 10, minutes: 5)), ex: 'Pec Deck'),
      _set(d.add(const Duration(hours: 10)), reps: 8),
      _set(DateTime(2026, 3, 6, 9), ex: 'Other'),
    ];
    vm.selectDate(d);
    expect(vm.session.map((e) => e.exercise), ['Bench Press', 'Pec Deck']);
    expect(vm.session[0].sets.map((s) => s.reps), [8, 6]);
  });

  test('returning to today restores today session', () {
    vm.addExercise('Chest', 'Bench Press');
    vm.logSet(0, _set(DateTime.now()));
    vm.previousDay();
    expect(vm.session, isEmpty);
    vm.nextDay();
    expect(vm.session.length, 1);
    expect(vm.session[0].sets.length, 1);
  });

  test('repeat last workout is today-only', () {
    vm.history = [_set(DateTime(2026, 3, 5, 10))];
    expect(vm.canRepeatLastWorkout, isTrue);
    vm.previousDay();
    expect(vm.canRepeatLastWorkout, isFalse);
  });

  test('logSet on a past day stores the set on that day', () {
    vm.selectDate(DateTime(2026, 3, 5));
    vm.addExercise('Chest', 'Bench Press');
    vm.logSet(0, _set(DateTime(2026, 10, 28, 15, 42, 7, 123)));
    final stored = vm.session[0].sets.single;
    expect(stored.date, DateTime(2026, 3, 5, 15, 42, 7, 123));
    expect(vm.history.first.date, stored.date);
    expect(vm.historyByDate['2026-03-05'], hasLength(1));
    vm.selectDate(DateTime.now());
    expect(vm.session, isEmpty);
  });
}
