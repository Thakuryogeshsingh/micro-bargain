import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../shared/widgets/motion.dart';

/// Pick a colour theme and light / dark / follow-phone mode.
class ThemeScreen extends ConsumerWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeProvider);
    final controller = ref.read(themeProvider.notifier);
    final modes = [
      (ThemeMode.system, Icons.brightness_auto_rounded, tr('फ़ोन जैसा')),
      (ThemeMode.light, Icons.light_mode_rounded, tr('लाइट')),
      (ThemeMode.dark, Icons.dark_mode_rounded, tr('डार्क')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('थीम'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('मोड'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.ink)),
        const SizedBox(height: 10),
        Row(children: [
          for (final (mode, icon, label) in modes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Pressable(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.setMode(mode);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: settings.mode == mode ? AppTheme.primaryDark : AppTheme.card,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AppTheme.softShadow(0.05),
                    ),
                    child: Column(children: [
                      Icon(icon, color: settings.mode == mode ? Colors.white : AppTheme.ink),
                      const SizedBox(height: 6),
                      Text(label,
                          style: TextStyle(fontWeight: FontWeight.w700, color: settings.mode == mode ? Colors.white : AppTheme.ink)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 24),
        Text(tr('रंग'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.ink)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            for (var i = 0; i < palettes.length; i++)
              FadeSlideIn(
                index: i,
                child: Pressable(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.setPalette(palettes[i].key);
                  },
                  child: _Swatch(palette: palettes[i], selected: settings.paletteKey == palettes[i].key),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => context.pop(), child: Text(tr('ठीक है'))),
      ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.selected});

  final AppPalette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? palette.primary : Colors.transparent, width: 3),
        boxShadow: AppTheme.softShadow(0.06),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (final c in [palette.primaryDark, palette.primary, palette.accent])
            Container(
              margin: const EdgeInsets.only(right: 6),
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          const Spacer(),
          if (selected) Icon(Icons.check_circle_rounded, color: palette.primary),
        ]),
        const Spacer(),
        Container(
          height: 10,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [palette.primaryDark, palette.primary]),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(height: 8),
        Text(tr(palette.label), style: TextStyle(fontWeight: FontWeight.w800, color: palette.primaryDark)),
      ]),
    );
  }
}

/// Settings list tile.
class ThemeTile extends ConsumerWidget {
  const ThemeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeProvider);
    return ListTile(
      leading: Icon(Icons.palette_rounded, color: settings.palette.primary),
      title: Text(tr('थीम')),
      subtitle: Text(tr(settings.palette.label)),
      onTap: () => context.push('/theme'),
    );
  }
}
