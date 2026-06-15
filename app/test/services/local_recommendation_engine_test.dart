import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/recommendation_models.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/local_recommendation_engine.dart';

/// Shorthand for building a test [WorkoutSet].
WorkoutSet ws(
  DateTime date,
  String exercise,
  String category,
  double weight,
  int reps, {
  String comment = '',
}) => WorkoutSet(
  date: date,
  exercise: exercise,
  category: category,
  weight: weight,
  reps: reps,
  comment: comment,
);

void main() {
  group('calcOneRM', () {
    test('returns 0 for zero reps', () {
      expect(LocalRecommendationEngine.calcOneRM(100, 0), 0.0);
    });

    test('returns 0 for zero weight', () {
      expect(LocalRecommendationEngine.calcOneRM(0, 5), 0.0);
    });

    // Brzycki (1–6 reps)
    test('Brzycki: 1 rep equals the weight itself', () {
      // 100 / (1.0278 - 0.0278 × 1) = 100 / 1.0000 = 100
      expect(LocalRecommendationEngine.calcOneRM(100, 1), closeTo(100.0, 0.01));
    });

    test('Brzycki: 6 reps', () {
      // 100 / (1.0278 - 0.1668) = 100 / 0.861 ≈ 116.1
      expect(LocalRecommendationEngine.calcOneRM(100, 6), closeTo(116.1, 0.2));
    });

    // Epley (7–11 reps)
    test('Epley: 7 reps', () {
      // 100 × (1 + 0.0333 × 7) = 100 × 1.2331 ≈ 123.3
      expect(LocalRecommendationEngine.calcOneRM(100, 7), closeTo(123.3, 0.2));
    });

    test('Epley: 11 reps', () {
      // 100 × (1 + 0.0333 × 11) = 100 × 1.3663 ≈ 136.6
      expect(LocalRecommendationEngine.calcOneRM(100, 11), closeTo(136.6, 0.2));
    });

    // Mayhew (12+ reps)
    test('Mayhew: 12 reps', () {
      // (100 × 100) / (52.2 + 41.9 × e^(−0.66)) ≈ 135.4
      expect(LocalRecommendationEngine.calcOneRM(100, 12), closeTo(135.4, 0.5));
    });

    test('Mayhew: higher reps produce a higher 1RM estimate', () {
      final rm20 = LocalRecommendationEngine.calcOneRM(100, 20);
      final rm12 = LocalRecommendationEngine.calcOneRM(100, 12);
      expect(rm20, greaterThan(rm12));
    });

    test('result scales linearly with weight', () {
      final rm200 = LocalRecommendationEngine.calcOneRM(200, 5);
      final rm100 = LocalRecommendationEngine.calcOneRM(100, 5);
      expect(rm200, closeTo(rm100 * 2, 0.01));
    });

    test('formula boundary: rep count 6 uses Brzycki, not Epley', () {
      // Brzycki(100, 6) ≠ Epley(100, 6); ensure the Brzycki path is taken
      final brzycki = 100 / (1.0278 - 0.0278 * 6);
      expect(
        LocalRecommendationEngine.calcOneRM(100, 6),
        closeTo(brzycki, 0.01),
      );
    });

    test('formula boundary: rep count 7 uses Epley, not Brzycki', () {
      final epley = 100 * (1 + 0.0333 * 7);
      expect(LocalRecommendationEngine.calcOneRM(100, 7), closeTo(epley, 0.01));
    });
  });
  group('recommend — new exercise', () {
    test('returns NEW EXERCISE status when history is empty', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: [],
      );
      expect(rec.status, contains('NEW EXERCISE'));
    });

    test('hypertrophy mode defaults to 10 reps and 0 weight', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: [],
        mode: TrainingMode.hypertrophy,
      );
      expect(rec.targetReps, 10);
      expect(rec.targetWeight, 0.0);
    });

    test('strength mode defaults to 5 reps and 0 weight', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: [],
        mode: TrainingMode.strength,
      );
      expect(rec.targetReps, 5);
      expect(rec.targetWeight, 0.0);
    });

    test('notesInsight mentions building up for new exercise', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Deadlift',
        category: 'Back',
        allHistory: [],
      );
      expect(rec.notesInsight, isNotEmpty);
    });
  });
  group('recommend — hypertrophy progression', () {
    final base = DateTime(2026, 1, 1);

    test('increases weight by 2.5 lbs when avg reps >= 12', () {
      final history = [
        ws(base, 'Bench Press', 'Chest', 100, 12),
        ws(base, 'Bench Press', 'Chest', 100, 12),
        ws(base, 'Bench Press', 'Chest', 100, 12),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
        mode: TrainingMode.hypertrophy,
      );
      expect(rec.targetWeight, 102.5);
      expect(rec.targetReps, 10);
      expect(rec.status, contains('HYPERTROPHY PROGRESSION'));
    });

    test('targets 12 reps (volume push) when avg reps are 8–11', () {
      final history = [
        ws(base, 'Bench Press', 'Chest', 100, 10),
        ws(base, 'Bench Press', 'Chest', 100, 10),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
        mode: TrainingMode.hypertrophy,
      );
      expect(rec.targetWeight, 100.0);
      expect(rec.targetReps, 12);
      expect(rec.status, contains('VOLUME'));
    });

    test('stabilizes at 10 reps when avg reps < 8', () {
      final history = [
        ws(base, 'Bench Press', 'Chest', 100, 6),
        ws(base, 'Bench Press', 'Chest', 100, 6),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
        mode: TrainingMode.hypertrophy,
      );
      expect(rec.targetWeight, 100.0);
      expect(rec.targetReps, 10);
      expect(rec.status, contains('STABILIZATION'));
    });

    test('default mode is hypertrophy when omitted', () {
      final history = [
        ws(base, 'Bench Press', 'Chest', 100, 12),
        ws(base, 'Bench Press', 'Chest', 100, 12),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
      );
      expect(rec.status, contains('HYPERTROPHY PROGRESSION'));
      expect(rec.targetWeight, 102.5);
    });
  });
  group('recommend — strength progression', () {
    final base = DateTime(2026, 1, 1);

    test('increases weight by 5.0 lbs when avg reps >= 6', () {
      final history = [
        ws(base, 'Squat', 'Legs', 200, 6),
        ws(base, 'Squat', 'Legs', 200, 6),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Squat',
        category: 'Legs',
        allHistory: history,
        mode: TrainingMode.strength,
      );
      expect(rec.targetWeight, 205.0);
      expect(rec.targetReps, 5);
      expect(rec.status, contains('STRENGTH PROGRESSION'));
    });

    test('targets 6 reps (volume push) when avg reps are 3–5', () {
      final history = [
        ws(base, 'Squat', 'Legs', 200, 5),
        ws(base, 'Squat', 'Legs', 200, 5),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Squat',
        category: 'Legs',
        allHistory: history,
        mode: TrainingMode.strength,
      );
      expect(rec.targetWeight, 200.0);
      expect(rec.targetReps, 6);
      expect(rec.status, contains('STRENGTH VOLUME'));
    });

    test('stabilizes at 4 reps when avg reps < 3', () {
      final history = [
        ws(base, 'Deadlift', 'Back', 300, 2),
        ws(base, 'Deadlift', 'Back', 300, 2),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Deadlift',
        category: 'Back',
        allHistory: history,
        mode: TrainingMode.strength,
      );
      expect(rec.targetWeight, 300.0);
      expect(rec.targetReps, 4);
      expect(rec.status, contains('STRENGTH STABILIZATION'));
    });
  });
  group('recommend — form issue', () {
    final base = DateTime(2026, 1, 1);

    test('holds weight and sets FORM FOCUS status', () {
      final history = [
        ws(
          base,
          'Overhead Press',
          'Shoulders',
          100,
          12,
          comment: 'form is off',
        ),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Overhead Press',
        category: 'Shoulders',
        allHistory: history,
      );
      expect(rec.targetWeight, 100.0);
      expect(rec.status, contains('FORM FOCUS'));
    });

    test('form issue blocks progression even when avg reps >= graduation', () {
      final history = [
        ws(base, 'Bench Press', 'Chest', 100, 12, comment: 'too heavy'),
        ws(base, 'Bench Press', 'Chest', 100, 12),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
        mode: TrainingMode.hypertrophy,
      );
      expect(rec.targetWeight, 100.0);
      expect(rec.status, contains('FORM FOCUS'));
    });

    test('form issue adds technique-focused notesInsight', () {
      final history = [ws(base, 'Squat', 'Legs', 200, 8, comment: 'sloppy')];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Squat',
        category: 'Legs',
        allHistory: history,
      );
      expect(rec.notesInsight.toLowerCase(), contains('form'));
    });

    test('multiple form-issue keywords are detected', () {
      for (final keyword in ['did it wrong', "couldn't", 'injury', 'failed']) {
        final history = [ws(base, 'Squat', 'Legs', 100, 8, comment: keyword)];
        final rec = LocalRecommendationEngine.recommend(
          exercise: 'Squat',
          category: 'Legs',
          allHistory: history,
        );
        expect(
          rec.status,
          contains('FORM FOCUS'),
          reason: 'expected FORM FOCUS for comment "$keyword"',
        );
      }
    });
  });
  group('recommend — fatigue detection', () {
    final base = DateTime(2026, 1, 1);

    test('adds fatigue notesInsight when fatigue keyword is present', () {
      final history = [
        ws(base, 'Lat Pulldown', 'Back', 100, 10, comment: 'forearm fatigued'),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Lat Pulldown',
        category: 'Back',
        allHistory: history,
      );
      expect(rec.notesInsight.toLowerCase(), contains('fatigue'));
    });

    test('no fatigue insight when comment is clean', () {
      final history = [
        ws(base, 'Lat Pulldown', 'Back', 100, 10, comment: 'good session'),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Lat Pulldown',
        category: 'Back',
        allHistory: history,
      );
      expect(rec.notesInsight.toLowerCase(), isNot(contains('fatigue')));
    });

    test('grip fatigue keyword is detected', () {
      final history = [
        ws(base, 'Pull Up', 'Back', 0, 8, comment: 'grip gave out'),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Pull Up',
        category: 'Back',
        allHistory: history,
      );
      expect(rec.notesInsight.toLowerCase(), contains('fatigue'));
    });
  });
  group('recommend — rep consistency', () {
    final base = DateTime(2026, 1, 1);

    test('rep drop (10→7→3) triggers stabilization status', () {
      // consistency = min(3,7,10) / mean(3,7,10) = 3/6.67 ≈ 0.45 < 0.5
      final history = [
        ws(base, 'Bench Press', 'Chest', 100, 10),
        ws(base, 'Bench Press', 'Chest', 100, 7),
        ws(base, 'Bench Press', 'Chest', 100, 3),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
        mode: TrainingMode.hypertrophy,
      );
      expect(rec.status, contains('Rep drop'));
    });

    test(
      'consistent reps (10→10→10) do not trigger rep-drop stabilization',
      () {
        final history = [
          ws(base, 'Bench Press', 'Chest', 100, 10),
          ws(base, 'Bench Press', 'Chest', 100, 10),
          ws(base, 'Bench Press', 'Chest', 100, 10),
        ];
        final rec = LocalRecommendationEngine.recommend(
          exercise: 'Bench Press',
          category: 'Chest',
          allHistory: history,
          mode: TrainingMode.hypertrophy,
        );
        expect(rec.status, isNot(contains('Rep drop')));
      },
    );

    test('single set per session has perfect consistency (no drop)', () {
      final history = [ws(base, 'Squat', 'Legs', 200, 8)];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Squat',
        category: 'Legs',
        allHistory: history,
      );
      expect(rec.status, isNot(contains('Rep drop')));
    });
  });
  group('recommend — AI override', () {
    // Three sessions with a steep weight decline at 6 reps (strength mode).
    // Sessions: 100 → 80 → 60 lbs.
    // Momentum ≈ −23 (well below −2 threshold).
    // Last 1RM ≈ 69.7 lbs < required1RM × 0.95 ≈ 72.0 lbs → override fires.
    final decliningHistory = [
      ws(DateTime(2026, 1, 1), 'Bench Press', 'Chest', 100, 6),
      ws(DateTime(2026, 1, 8), 'Bench Press', 'Chest', 80, 6),
      ws(DateTime(2026, 1, 15), 'Bench Press', 'Chest', 60, 6),
    ];

    test('triggers AI OVERRIDE on a declining trend with low capacity', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: decliningHistory,
        mode: TrainingMode.strength,
      );
      expect(rec.status, contains('AI OVERRIDE'));
    });

    test('AI override adds a declining-trend notesInsight', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: decliningHistory,
        mode: TrainingMode.strength,
      );
      expect(rec.notesInsight.toLowerCase(), contains('declining'));
    });

    test('strong positive momentum adds a climbing notesInsight', () {
      // Sessions: 100 → 120 → 150 lbs at 8 reps — momentum ≈ +32
      final risingHistory = [
        ws(DateTime(2026, 1, 1), 'Squat', 'Legs', 100, 8),
        ws(DateTime(2026, 1, 8), 'Squat', 'Legs', 120, 8),
        ws(DateTime(2026, 1, 15), 'Squat', 'Legs', 150, 8),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Squat',
        category: 'Legs',
        allHistory: risingHistory,
        mode: TrainingMode.hypertrophy,
      );
      expect(rec.notesInsight.toLowerCase(), contains('momentum'));
    });
  });
  group('recommend — set exclusions', () {
    final base = DateTime(2026, 1, 1);

    test('all drop sets → returns NEW EXERCISE', () {
      final history = [
        ws(base, 'Curl', 'Biceps', 40, 12, comment: 'drop set'),
        ws(base, 'Curl', 'Biceps', 30, 15, comment: 'no rest'),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Curl',
        category: 'Biceps',
        allHistory: history,
      );
      expect(rec.status, contains('NEW EXERCISE'));
    });

    test('all warm-up tagged sets → returns NEW EXERCISE', () {
      final history = [
        ws(base, 'Bench Press', 'Chest', 45, 15, comment: 'warm up'),
        ws(base, 'Bench Press', 'Chest', 45, 15, comment: 'warm-up'),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
      );
      expect(rec.status, contains('NEW EXERCISE'));
    });

    test('weight-based warm-ups (< 60 % of session max) are excluded', () {
      // 45 lbs < 60 % of 135 lbs → excluded; only 135-lb sets count
      final history = [
        ws(base, 'Bench Press', 'Chest', 45, 15),
        ws(base, 'Bench Press', 'Chest', 135, 8),
        ws(base, 'Bench Press', 'Chest', 135, 8),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
        mode: TrainingMode.hypertrophy,
      );
      // lastMaxW = 135 (not 45), avgReps = 8 → VOLUME push
      expect(rec.targetWeight, 135.0);
      expect(rec.status, contains('VOLUME'));
    });

    test('sets from a different exercise are ignored', () {
      final history = [
        ws(base, 'Squat', 'Legs', 200, 5),
        ws(base, 'Leg Press', 'Legs', 400, 10), // different exercise
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Squat',
        category: 'Legs',
        allHistory: history,
        mode: TrainingMode.strength,
      );
      expect(rec.targetWeight, 200.0);
    });
  });
  group('recommend — bodyweight', () {
    final base = DateTime(2026, 1, 1);

    test('returns BODYWEIGHT status when weight is 0', () {
      final history = [
        ws(base, 'Pull Up', 'Back', 0, 8),
        ws(base, 'Pull Up', 'Back', 0, 8),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Pull Up',
        category: 'Back',
        allHistory: history,
      );
      expect(rec.status, contains('BODYWEIGHT'));
    });

    test('bodyweight progression increases target reps past graduation', () {
      // avgReps = 12 >= graduationReps (12) → reps should exceed default
      final history = [
        ws(base, 'Pull Up', 'Back', 0, 12),
        ws(base, 'Pull Up', 'Back', 0, 12),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Pull Up',
        category: 'Back',
        allHistory: history,
        mode: TrainingMode.hypertrophy,
      );
      expect(rec.targetReps, greaterThan(12));
    });
  });
  group('recommend — multi-session history', () {
    test('uses the most recent session for weight/rep decisions', () {
      // Session 1 (older): 100 lbs × 8; Session 2 (newer): 120 lbs × 12
      final history = [
        ws(DateTime(2026, 1, 1), 'Bench Press', 'Chest', 100, 8),
        ws(DateTime(2026, 1, 8), 'Bench Press', 'Chest', 120, 12),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
        mode: TrainingMode.hypertrophy,
      );
      // Last session max = 120, avgReps = 12 → PROGRESSION, +2.5
      expect(rec.targetWeight, 122.5);
    });

    test('two sessions with steady reps produce no AI override', () {
      final history = [
        ws(DateTime(2026, 1, 1), 'Squat', 'Legs', 100, 8),
        ws(DateTime(2026, 1, 8), 'Squat', 'Legs', 100, 8),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Squat',
        category: 'Legs',
        allHistory: history,
      );
      expect(rec.status, isNot(contains('AI OVERRIDE')));
    });

    test('predicted1RM reflects the last session max set', () {
      final history = [
        ws(DateTime(2026, 1, 1), 'Bench Press', 'Chest', 135, 8),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
      );
      // Epley(135, 8) = 135 × (1 + 0.0333 × 8) ≈ 170.97
      expect(rec.predicted1RM, closeTo(170.97, 0.5));
    });
  });

  group('recommend — plateau detection', () {
    List<WorkoutSet> fourStableSessions({String lastComment = ''}) {
      final base = DateTime(2026, 1, 1);
      return [
        ws(base, 'Bench Press', 'Chest', 135.0, 8),
        ws(base.add(const Duration(days: 7)), 'Bench Press', 'Chest', 135.0, 8),
        ws(
          base.add(const Duration(days: 14)),
          'Bench Press',
          'Chest',
          135.0,
          8,
        ),
        ws(
          base.add(const Duration(days: 21)),
          'Bench Press',
          'Chest',
          135.0,
          8,
          comment: lastComment,
        ),
      ];
    }

    test('four sessions with no 1RM gain triggers DELOAD status', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: fourStableSessions(),
      );
      expect(rec.status, contains('DELOAD'));
    });

    test('deload sets target reps to 15', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: fourStableSessions(),
      );
      expect(rec.targetReps, 15);
    });

    test('deload reduces target weight to 60 % of last max rounded to 2.5', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: fourStableSessions(),
      );
      // ((135 * 0.6) / 2.5).round() * 2.5 = 32.4.round() * 2.5 = 32 * 2.5 = 80
      expect(rec.targetWeight, closeTo(80.0, 0.01));
    });

    test('plateau insight message is included in notesInsight', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: fourStableSessions(),
      );
      expect(rec.notesInsight.toLowerCase(), contains('4 sessions'));
    });

    test('five sessions with small gain still plateaus', () {
      final base = DateTime(2026, 1, 1);
      final history = [
        ws(base, 'Bench Press', 'Chest', 135.0, 8),
        ws(base.add(const Duration(days: 7)), 'Bench Press', 'Chest', 135.0, 8),
        ws(
          base.add(const Duration(days: 14)),
          'Bench Press',
          'Chest',
          135.5,
          8,
        ),
        ws(
          base.add(const Duration(days: 21)),
          'Bench Press',
          'Chest',
          135.0,
          8,
        ),
        ws(
          base.add(const Duration(days: 28)),
          'Bench Press',
          'Chest',
          135.0,
          8,
        ),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
      );
      expect(rec.status, contains('DELOAD'));
    });

    test('form issue takes priority over plateau', () {
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: fourStableSessions(lastComment: 'did it wrong'),
      );
      expect(rec.status, contains('FORM FOCUS'));
    });

    test('three sessions does not trigger plateau even with stable 1RM', () {
      final base = DateTime(2026, 1, 1);
      final history = [
        ws(base, 'Bench Press', 'Chest', 135.0, 8),
        ws(base.add(const Duration(days: 7)), 'Bench Press', 'Chest', 135.0, 8),
        ws(
          base.add(const Duration(days: 14)),
          'Bench Press',
          'Chest',
          135.0,
          8,
        ),
      ];
      final rec = LocalRecommendationEngine.recommend(
        exercise: 'Bench Press',
        category: 'Chest',
        allHistory: history,
      );
      expect(rec.status, isNot(contains('DELOAD')));
    });
  });
}
