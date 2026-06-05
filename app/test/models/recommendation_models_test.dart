import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/recommendation_models.dart';

void main() {
  group('Recommendation — fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'target_reps': 8,
        'target_weight': 135.0,
        'status': 'HYPERTROPHY PROGRESSION: Weight Increased',
        'predicted_1rm': 161.0,
        'required_1rm': 155.0,
        'notes_insight': 'Strong momentum!',
      };
      final rec = Recommendation.fromJson(json);
      expect(rec.targetReps, 8);
      expect(rec.targetWeight, 135.0);
      expect(rec.status, 'HYPERTROPHY PROGRESSION: Weight Increased');
      expect(rec.predicted1RM, 161.0);
      expect(rec.required1RM, 155.0);
      expect(rec.notesInsight, 'Strong momentum!');
    });

    test('defaults notesInsight to empty string when key is absent', () {
      final json = {
        'target_reps': 5,
        'target_weight': 200.0,
        'status': 'STRENGTH PROGRESSION: Weight Increased',
        'predicted_1rm': 225.0,
        'required_1rm': 210.0,
      };
      final rec = Recommendation.fromJson(json);
      expect(rec.notesInsight, '');
    });

    test('parses integer target_weight as double', () {
      final json = {
        'target_reps': 5,
        'target_weight': 200,
        'status': 'STRENGTH PROGRESSION: Weight Increased',
        'predicted_1rm': 225,
        'required_1rm': 210,
        'notes_insight': '',
      };
      final rec = Recommendation.fromJson(json);
      expect(rec.targetWeight, isA<double>());
      expect(rec.targetWeight, 200.0);
    });
  });

  group('Recommendation — const constructor', () {
    test('default notesInsight is empty string', () {
      const rec = Recommendation(
        targetReps: 8,
        targetWeight: 100.0,
        status: 'VOLUME',
        predicted1RM: 120.0,
        required1RM: 110.0,
      );
      expect(rec.notesInsight, '');
    });
  });

  group('TrainingMode', () {
    test('contains hypertrophy and strength values', () {
      expect(TrainingMode.values, containsAll([
        TrainingMode.hypertrophy,
        TrainingMode.strength,
      ]));
    });

    test('enum name matches the identifier string', () {
      expect(TrainingMode.hypertrophy.name, 'hypertrophy');
      expect(TrainingMode.strength.name, 'strength');
    });

    test('values are distinct', () {
      expect(TrainingMode.hypertrophy, isNot(TrainingMode.strength));
    });
  });
}
