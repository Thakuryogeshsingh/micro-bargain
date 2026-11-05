import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_theme.dart';

class ThemeSettings {
  const ThemeSettings({this.paletteKey = 'forest', this.mode = ThemeMode.system});

  final String paletteKey;
  final ThemeMode mode;

  AppPalette get palette => palettes.firstWhere((p) => p.key == paletteKey, orElse: () => palettes.first);
}

/// Chosen colour palette and light/dark mode, saved on the phone.
class ThemeController extends Notifier<ThemeSettings> {
  static const _storage = FlutterSecureStorage();

  @override
  ThemeSettings build() => const ThemeSettings();

  Future<void> restore() async {
    final palette = await _storage.read(key: 'theme_palette');
    final mode = await _storage.read(key: 'theme_mode');
    state = ThemeSettings(
      paletteKey: palette ?? 'forest',
      mode: ThemeMode.values.firstWhere((m) => m.name == mode, orElse: () => ThemeMode.system),
    );
  }

  Future<void> setPalette(String key) async {
    await _storage.write(key: 'theme_palette', value: key);
    state = ThemeSettings(paletteKey: key, mode: state.mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    await _storage.write(key: 'theme_mode', value: mode.name);
    state = ThemeSettings(paletteKey: state.paletteKey, mode: mode);
  }
}

final themeProvider = NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);

/// Whether the welcome slides were already shown on this phone.
class OnboardingController extends Notifier<bool> {
  static const _storage = FlutterSecureStorage();

  @override
  bool build() => false;

  Future<void> restore() async => state = await _storage.read(key: 'onboarded') == 'yes';

  Future<void> finish() async {
    await _storage.write(key: 'onboarded', value: 'yes');
    state = true;
  }
}

final onboardedProvider = NotifierProvider<OnboardingController, bool>(OnboardingController.new);
