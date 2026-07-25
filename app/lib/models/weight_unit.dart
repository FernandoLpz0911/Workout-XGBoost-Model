/// The user's preferred unit for *displaying* weight values. All sets and
/// body measurements are always stored internally in lbs; this only affects
/// presentation and how typed input is converted back to lbs.
enum WeightUnit { lbs, kg }

const kgPerLb = 0.45359237;

double lbsToDisplay(double lbs, WeightUnit unit) =>
    unit == WeightUnit.kg ? lbs * kgPerLb : lbs;

double displayToLbs(double value, WeightUnit unit) =>
    unit == WeightUnit.kg ? value / kgPerLb : value;

String weightUnitLabel(WeightUnit unit) => unit == WeightUnit.kg ? 'kg' : 'lbs';
