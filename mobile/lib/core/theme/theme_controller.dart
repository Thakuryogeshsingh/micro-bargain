import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs.dart';
import 'app_theme.dart';

class ThemeSettings {
  const ThemeSettings({this.paletteKey = 'fresh', this.mode = ThemeMode.system});

  final String paletteKey;
  final ThemeMode mode;

  AppPalette get palette => palettes.firstWhere((p) => p.key == paletteKey, orElse: () => palettes.first);
}

/// Chosen colour palette and light/dark mode, saved on the phone.
class ThemeController extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() => const ThemeSettings();

  Future<void> restore() async {
    final palette = Prefs.get('theme_palette');
    final mode = Prefs.get('theme_mode');
    state = ThemeSettings(
      paletteKey: palette ?? 'fresh',
      mode: ThemeMode.values.firstWhere((m) => m.name == mode, orElse: () => ThemeMode.system),
    );
  }

  Future<void> setPalette(String key) async {
    await Prefs.set('theme_palette', key);
    state = ThemeSettings(paletteKey: key, mode: state.mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    await Prefs.set('theme_mode', mode.name);
    state = ThemeSettings(paletteKey: state.paletteKey, mode: mode);
  }
}

final themeProvider = NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);

/// Whether the welcome slides were already shown on this phone.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> restore() async => state = Prefs.get('onboarded') == 'yes';

  Future<void> finish() async {
    await Prefs.set('onboarded', 'yes');
    state = true;
  }
}

final onboardedProvider = NotifierProvider<OnboardingController, bool>(OnboardingController.new);
