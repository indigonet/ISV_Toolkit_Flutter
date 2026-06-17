import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistence of user preferences (theme mode and language).
class PreferencesService {
  static const _keyDarkMode = 'pref_dark_mode';
  static const _keyLanguage = 'pref_language';
  static const _keyOutputDir = 'pref_output_dir';

  final SharedPreferences _prefs;

  PreferencesService._(this._prefs);

  /// Factory: loads SharedPreferences and returns a ready instance.
  static Future<PreferencesService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService._(prefs);
  }

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isDarkMode => _prefs.getBool(_keyDarkMode) ?? false;
  String get language => _prefs.getString(_keyLanguage) ?? 'es';
  String get outputDir => _prefs.getString(_keyOutputDir) ?? '';

  // ── Setters ──────────────────────────────────────────────────────────────

  Future<void> setDarkMode(bool value) => _prefs.setBool(_keyDarkMode, value);

  Future<void> setLanguage(String value) =>
      _prefs.setString(_keyLanguage, value);

  Future<void> setOutputDir(String value) =>
      _prefs.setString(_keyOutputDir, value);
}
