import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/workout_set.dart';

void main() {
  group('WorkoutSet — toJson / fromJson round-trip', () {
    test('strength set preserves all fields', () {
      final original = WorkoutSet(
        date: DateTime(2026, 1, 15, 10, 30, 0),
        exercise: 'Bench Press',
        category: 'Chest',
        weight: 135.0,
        reps: 8,
        comment: 'felt strong',
      );
      final restored = WorkoutSet.fromJson(original.toJson());
      expect(restored.date.millisecondsSinceEpoch,
          original.date.millisecondsSinceEpoch);
      expect(restored.exercise, original.exercise);
      expect(restored.category, original.category);
      expect(restored.weight, original.weight);
      expect(restored.reps, original.reps);
      expect(restored.comment, original.comment);
    });

    test('cardio set preserves distance, unit, and duration', () {
      final original = WorkoutSet(
        date: DateTime(2026, 3, 1),
        exercise: 'General Running',
        category: 'Cardio',
        distance: 3.14,
        distanceUnit: 'mi',
        duration: '0:28:00',
        comment: '',
      );
      final restored = WorkoutSet.fromJson(original.toJson());
      expect(restored.distance, original.distance);
      expect(restored.distanceUnit, original.distanceUnit);
      expect(restored.duration, original.duration);
      expect(restored.weight, 0.0);
      expect(restored.reps, 0);
    });

    test('passive set round-trips correctly', () {
      final original = WorkoutSet(
        date: DateTime(2026, 3, 1),
        exercise: 'Sauna',
        category: 'Passive',
        duration: '0:20:00',
      );
      final restored = WorkoutSet.fromJson(original.toJson());
      expect(restored.exercise, 'Sauna');
      expect(restored.duration, '0:20:00');
      expect(restored.weight, 0.0);
      expect(restored.reps, 0);
    });

    test('fromJson accepts date-only string without time component', () {
      final json = {
        'date': '2026-05-28',
        'exercise': 'Squat',
        'category': 'Legs',
        'weight': 200.0,
        'reps': 5,
        'comment': '',
      };
      final set = WorkoutSet.fromJson(json);
      expect(set.date.year, 2026);
      expect(set.date.month, 5);
      expect(set.date.day, 28);
    });

    test('toJson omits null optional fields', () {
      final set = WorkoutSet(
        date: DateTime(2026, 1, 1),
        exercise: 'Pull Up',
        category: 'Back',
        reps: 10,
      );
      final json = set.toJson();
      expect(json.containsKey('distance'), isFalse);
      expect(json.containsKey('distanceUnit'), isFalse);
      expect(json.containsKey('duration'), isFalse);
    });

    test('fromJson defaults missing numeric fields to zero', () {
      final json = {
        'date': '2026-01-01',
        'exercise': 'Push Up',
        'category': 'Chest',
        'comment': '',
      };
      final set = WorkoutSet.fromJson(json);
      expect(set.weight, 0.0);
      expect(set.reps, 0);
    });
  });

  group('WorkoutSet — toCsvRow', () {
    test('strength set produces correct FitNotes-compatible columns', () {
      final set = WorkoutSet(
        date: DateTime(2026, 3, 5),
        exercise: 'Bench Press',
        category: 'Chest',
        weight: 135.0,
        reps: 8,
        comment: 'good set',
      );
      final row = set.toCsvRow();
      expect(row, startsWith('2026-03-05,"Bench Press","Chest",135.0,lbs,8'));
      expect(row, contains('"good set"'));
    });

    test('cardio set includes distance, unit, and duration', () {
      final set = WorkoutSet(
        date: DateTime(2026, 3, 5),
        exercise: 'General Running',
        category: 'Cardio',
        distance: 3.14,
        distanceUnit: 'mi',
        duration: '0:28:00',
        comment: '',
      );
      final row = set.toCsvRow();
      expect(row, contains('3.14'));
      expect(row, contains('mi'));
      expect(row, contains('0:28:00'));
    });

    test('escapes double-quotes inside comment field', () {
      final set = WorkoutSet(
        date: DateTime(2026, 1, 1),
        exercise: 'Curl',
        category: 'Biceps',
        weight: 40.0,
        reps: 10,
        comment: 'felt "great" today',
      );
      expect(set.toCsvRow(), contains('"felt ""great"" today"'));
    });

    test('empty weight and reps produce empty columns', () {
      final set = WorkoutSet(
        date: DateTime(2026, 1, 1),
        exercise: 'Sauna',
        category: 'Passive',
        duration: '0:15:00',
        comment: '',
      );
      final parts = set.toCsvRow().split(',');
      expect(parts[3], ''); // weight column
      expect(parts[4], ''); // weight unit column
      expect(parts[5], ''); // reps column
    });
  });

  group('WorkoutSet — displayText', () {
    test('strength set shows weight × reps', () {
      final set = WorkoutSet(
        date: DateTime.now(),
        exercise: 'Squat',
        category: 'Legs',
        weight: 225.0,
        reps: 5,
      );
      expect(set.displayText, '225.0 lbs × 5');
    });

    test('cardio with duration shows distance @ pace', () {
      final set = WorkoutSet(
        date: DateTime.now(),
        exercise: 'General Running',
        category: 'Cardio',
        distance: 3.0,
        distanceUnit: 'mi',
        duration: '0:24:00',
      );
      expect(set.displayText, '3.00 mi @ 0:24:00');
    });

    test('cardio without duration shows distance only', () {
      final set = WorkoutSet(
        date: DateTime.now(),
        exercise: 'Cycling',
        category: 'Cardio',
        distance: 10.0,
        distanceUnit: 'km',
      );
      expect(set.displayText, '10.00 km');
    });

    test('time-based set (duration only) shows the duration string', () {
      final set = WorkoutSet(
        date: DateTime.now(),
        exercise: 'Dead Hang',
        category: 'Back',
        duration: '0:01:30',
      );
      expect(set.displayText, '0:01:30');
    });
  });

  group('WorkoutSet — fmtDateStatic', () {
    test('pads month and day with leading zeros', () {
      expect(WorkoutSet.fmtDateStatic(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('formats double-digit month and day correctly', () {
      expect(WorkoutSet.fmtDateStatic(DateTime(2026, 11, 20)), '2026-11-20');
    });
  });
}
