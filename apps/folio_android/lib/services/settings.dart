import 'package:flutter/foundation.dart';
import 'package:folio_catalog/folio_catalog.dart';
import 'package:folio_core/folio_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences. The primary source URL lives here, never in the repo.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  final SharedPreferences _prefs;

  static const _primaryKey = 'primaryBaseUrl';
  static const _themeKey = 'readerTheme';
  static const _fontKey = 'readerFontSize';

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  String get primaryBaseUrl => _prefs.getString(_primaryKey) ?? placeholderPrimaryUrl;

  Future<void> setPrimaryBaseUrl(String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      await _prefs.remove(_primaryKey);
    } else {
      await _prefs.setString(_primaryKey, v);
    }
    notifyListeners();
  }

  ReaderStyle get readerStyle => ReaderStyle(
        theme: ReaderTheme.values.asNameMap()[_prefs.getString(_themeKey)] ?? ReaderTheme.light,
        fontSize: _prefs.getInt(_fontKey) ?? 100,
      );

  Future<void> setReaderStyle(ReaderStyle style) async {
    await _prefs.setString(_themeKey, style.theme.name);
    await _prefs.setInt(_fontKey, style.fontSize);
    notifyListeners();
  }
}
