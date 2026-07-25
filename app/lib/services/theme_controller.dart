import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:repiq/theme/app_theme.dart';

/// Persists and exposes the user's chosen [AppThemeId], defaulting to
/// [AppThemeId.midnight] (the app's original look) until a saved
/// preference loads.
class ThemeController extends ChangeNotifier {
  static const _prefsKey = 'app_theme_id_v1';

  AppThemeId _themeId = AppThemeId.midnight;
  AppThemeId get themeId => _themeId;

  ThemeController() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    final match = AppThemeId.values.where((v) => v.name == saved);
    if (match.isNotEmpty) {
      _themeId = match.first;
      notifyListeners();
    }
  }

  Future<void> setTheme(AppThemeId id) async {
    if (id == _themeId) return;
    _themeId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id.name);
  }
}
