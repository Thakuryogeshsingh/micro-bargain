import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plain app settings (language, theme, "welcome shown"). Not secrets, so they live in normal
/// SharedPreferences: on some phones the encrypted store comes back empty after a restart or update,
/// which made the language and welcome screens appear again on every launch.
class Prefs {
  static SharedPreferences? _prefs;

  static const _keys = ['language', 'onboarded', 'theme_palette', 'theme_mode'];

  /// Call once in main() before anything reads a setting.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _moveFromSecureStorage();
  }

  static String? get(String key) => _prefs?.getString(key);

  static Future<void> set(String key, String value) async => _prefs?.setString(key, value);

  static Future<void> remove(String key) async => _prefs?.remove(key);

  /// Older versions saved these in the encrypted store; copy them over once so nobody is asked again.
  static Future<void> _moveFromSecureStorage() async {
    final prefs = _prefs!;
    if (prefs.getBool('moved_from_secure') == true) return;
    try {
      const secure = FlutterSecureStorage();
      for (final key in _keys) {
        final value = await secure.read(key: key);
        if (value != null && prefs.getString(key) == null) await prefs.setString(key, value);
      }
    } catch (_) {
      // Unreadable encrypted store: nothing to move.
    }
    await prefs.setBool('moved_from_secure', true);
  }
}
