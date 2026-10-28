import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/exercise_picker_logic.dart';

WorkoutSet _set(String cat, String ex, DateTime d) =>
    WorkoutSet(date: d, exercise: ex, category: cat, weight: 100, reps: 5);

void main() {
  group('recentExercises', () {
    test('most recent first, deduplicated', () {
      final h = [
        _set('Chest', 'Bench', DateTime(2025, 1, 1)),
        _set('Legs', 'Squat', DateTime(2025, 1, 3)),
        _set('Chest', 'Bench', DateTime(2025, 1, 5)),
      ];
      final r = recentExercises(h);
      expect(r.map((e) => e.exercise), ['Bench', 'Squat']);
      expect(r.first.category, 'Chest');
    });

    test('limits to 8', () {
      final h = [
        for (var i = 0; i < 12; i++) _set('C', 'E$i', DateTime(2025, 1, 1 + i)),
      ];
      final r = recentExercises(h);
      expect(r.length, 8);
      expect(r.first.exercise, 'E11');
    });

    test('empty history', () => expect(recentExercises([]), isEmpty));
  });

  group('categorySummaries', () {
    test('counts exercises per category, keeps category order', () {
      final s = categorySummaries({
        'Legs': ['Squat'],
        'Chest': ['Bench', 'Fly'],
      });
      expect(s.map((c) => c.name), ['Legs', 'Chest']);
      expect(s.map((c) => c.count), [1, 2]);
    });
  });

  group('searchExercises', () {
    final data = {
      'Chest': ['Bench Press', 'Fly'],
      'Legs': ['Squat', 'Leg Press'],
    };
    test('case-insensitive substring across categories', () {
      final r = searchExercises(data, 'PRESS');
      expect(r.map((e) => e.exercise), ['Bench Press', 'Leg Press']);
      expect(r.last.category, 'Legs');
    });
    test('blank query returns nothing', () {
      expect(searchExercises(data, '  '), isEmpty);
    });
    test('trims query', () {
      expect(searchExercises(data, ' fly ').length, 1);
    });
  });

  test('sortedExercises sorts case-insensitively', () {
    expect(sortedExercises(['b', 'A', 'c']), ['A', 'b', 'c']);
  });
}
