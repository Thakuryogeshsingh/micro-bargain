import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/session.dart';
import 'core/i18n/i18n.dart';
import 'core/network/api_client.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/notifications/notifications_screen.dart';

final _messengerKey = GlobalKey<ScaffoldMessengerState>();

class MicroBargainApp extends ConsumerWidget {
  const MicroBargainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // After each login, register this phone for push notifications.
    ref.listen(sessionProvider, (previous, next) {
      if (next.status == SessionStatus.signedIn && previous?.status != SessionStatus.signedIn) {
        PushService.register(ref.read(apiProvider), onForegroundMessage: (message) {
          ref.invalidate(unreadCountProvider);
          final title = message.notification?.title;
          if (title != null) _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(title)));
        });
      }
    });

    final language = ref.watch(languageProvider) ?? 'hi';
    final theme = ref.watch(themeProvider);
    AppTheme.palette = theme.palette;
    return MaterialApp.router(
      // A new key rebuilds every screen, so all tr() texts and theme colours switch at once.
      key: ValueKey('$language-${theme.paletteKey}-${theme.mode.name}'),
      locale: Locale(language),
      supportedLocales: [for (final l in languages) Locale(l.code)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: 'Micro Bargain',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(theme.palette, Brightness.light),
      darkTheme: AppTheme.build(theme.palette, Brightness.dark),
      themeMode: theme.mode,
      scaffoldMessengerKey: _messengerKey,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        AppTheme.dark = brightness == Brightness.dark;
        return MediaQuery(
          // Very large system font sizes clipped text in fixed-height cards; allow up to 115%.
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.textScalerOf(context).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
          ),
          // Rebuild everything when the phone switches between light and dark ("system" mode).
          // Status bar icons: dark on the light (white-header) screens, light in dark mode.
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: KeyedSubtree(key: ValueKey(brightness), child: child!),
          ),
        );
      },
    );
  }
}
