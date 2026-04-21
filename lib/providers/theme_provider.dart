import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/nexaryo_colors.dart';

class ThemeProvider extends ChangeNotifier {
  String _activeId = 'ember';
  bool _isDark = false;

  String get activeId => _activeId;
  bool get isDark => _isDark;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  NexaryoPalette get _activePalette =>
      NexaryoColors.palettes.firstWhere((p) => p.id == _activeId);

  NexaryoColors get darkColors => _activePalette.dark;
  NexaryoColors get lightColors => _activePalette.light;
  NexaryoColors get colors => _isDark ? darkColors : lightColors;

  void setTheme(String id) {
    if (_activeId == id) return;
    _activeId = id;
    notifyListeners();
    _save();
  }

  void setDarkMode(bool value) {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
    _save();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString('theme_active_id') ?? 'ember';
    _activeId = NexaryoColors.palettes.any((p) => p.id == storedId)
        ? storedId
        : 'ember';
    _isDark = prefs.getBool('theme_is_dark') ?? false;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_active_id', _activeId);
    await prefs.setBool('theme_is_dark', _isDark);
  }
}
