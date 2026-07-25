import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:repiq/models/weight_unit.dart';

/// Persists and exposes the user's preferred weight display unit, defaulting
/// to [WeightUnit.lbs] until a saved preference loads.
class UnitsController extends ChangeNotifier {
  static const _prefsKey = 'weight_unit_v1';

  WeightUnit _unit = WeightUnit.lbs;
  WeightUnit get unit => _unit;
  String get label => weightUnitLabel(_unit);

  /// Round increment step for weight steppers, in the current display unit.
  double get step => _unit == WeightUnit.kg ? 1.0 : 2.5;

  UnitsController() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    final match = WeightUnit.values.where((v) => v.name == saved);
    if (match.isNotEmpty) {
      _unit = match.first;
      notifyListeners();
    }
  }

  Future<void> setUnit(WeightUnit u) async {
    if (u == _unit) return;
    _unit = u;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, u.name);
  }

  double toDisplay(double lbs) => lbsToDisplay(lbs, _unit);
  double toLbs(double displayValue) => displayToLbs(displayValue, _unit);
}
