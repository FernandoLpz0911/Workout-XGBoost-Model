import 'package:flutter_test/flutter_test.dart';
import 'package:repiq/models/weight_unit.dart';

void main() {
  group('lbsToDisplay', () {
    test('returns the value unchanged for lbs', () {
      expect(lbsToDisplay(200.0, WeightUnit.lbs), 200.0);
    });

    test('converts to kg', () {
      expect(lbsToDisplay(100.0, WeightUnit.kg), closeTo(45.359, 0.001));
    });
  });

  group('displayToLbs', () {
    test('returns the value unchanged for lbs', () {
      expect(displayToLbs(200.0, WeightUnit.lbs), 200.0);
    });

    test('converts from kg back to lbs', () {
      expect(displayToLbs(45.359237, WeightUnit.kg), closeTo(100.0, 0.001));
    });

    test('round-trips through toDisplay and back', () {
      const original = 135.0;
      final kg = lbsToDisplay(original, WeightUnit.kg);
      expect(displayToLbs(kg, WeightUnit.kg), closeTo(original, 0.0001));
    });
  });

  group('weightUnitLabel', () {
    test('labels lbs', () {
      expect(weightUnitLabel(WeightUnit.lbs), 'lbs');
    });

    test('labels kg', () {
      expect(weightUnitLabel(WeightUnit.kg), 'kg');
    });
  });
}
