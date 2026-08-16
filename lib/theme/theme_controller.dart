import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_variant.dart';

/// Holds the user's [ThemeVariant] selection and persists it across launches.
class ThemeController extends ChangeNotifier {
  static const String _prefsKey = 'theme_variant';

  ThemeVariant _variant = ThemeVariant.dynamic;

  ThemeVariant get variant => _variant;

  /// Restores the saved variant (defaults to Dynamic). Unknown saved values
  /// (e.g. from an older version with more themes) fall back to Dynamic.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefsKey);
    if (name == null) return;
    _variant = ThemeVariant.values.firstWhere(
      (v) => v.name == name,
      orElse: () => ThemeVariant.dynamic,
    );
    notifyListeners();
  }

  Future<void> setVariant(ThemeVariant variant) async {
    if (variant == _variant) return;
    _variant = variant;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, variant.name);
  }
}
