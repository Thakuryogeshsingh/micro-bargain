import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs.dart';

/// App languages. The UI is written in Hindi; every Hindi text is the key into assets/i18n/<code>.json.
class AppLanguage {
  const AppLanguage(this.code, this.nativeName, this.englishName);

  final String code;
  final String nativeName;
  final String englishName;
}

const languages = [
  AppLanguage('hi', 'हिन्दी', 'Hindi'),
  AppLanguage('en', 'English', 'English'),
  AppLanguage('bn', 'বাংলা', 'Bengali'),
  AppLanguage('mr', 'मराठी', 'Marathi'),
  AppLanguage('te', 'తెలుగు', 'Telugu'),
  AppLanguage('ta', 'தமிழ்', 'Tamil'),
  AppLanguage('gu', 'ગુજરાતી', 'Gujarati'),
  AppLanguage('kn', 'ಕನ್ನಡ', 'Kannada'),
  AppLanguage('ml', 'മലയാളം', 'Malayalam'),
  AppLanguage('pa', 'ਪੰਜਾਬੀ', 'Punjabi'),
  AppLanguage('or', 'ଓଡ଼ିଆ', 'Odia'),
  AppLanguage('as', 'অসমীয়া', 'Assamese'),
  AppLanguage('ur', 'اردو', 'Urdu'),
];

Map<String, String> _catalogue = const {};

/// Translates a Hindi UI text into the chosen language. Placeholders {0}, {1}… are filled from [args].
/// Unknown texts (or Hindi itself) are returned unchanged, so a missing translation shows Hindi, never blank.
String tr(String key, [List<Object?> args = const []]) {
  var text = _catalogue[key] ?? key;
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', '${args[i]}');
  }
  return text;
}

const _storageKey = 'language';

/// The chosen language code, or null before the user has picked one (first launch).
class LanguageController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Called once at startup, before the first frame.
  Future<void> restore() async {
    final saved = Prefs.get(_storageKey);
    if (saved != null) await _apply(saved);
  }

  Future<void> choose(String code) async {
    await Prefs.set(_storageKey, code);
    await _apply(code);
  }

  Future<void> _apply(String code) async {
    if (code == 'hi') {
      _catalogue = const {};
    } else {
      final raw = await rootBundle.loadString('assets/i18n/$code.json');
      _catalogue = Map<String, String>.from(jsonDecode(raw) as Map);
    }
    state = code;
  }
}

final languageProvider = NotifierProvider<LanguageController, String?>(LanguageController.new);
