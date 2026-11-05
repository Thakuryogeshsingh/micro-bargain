import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/session.dart';
import 'core/i18n/i18n.dart';
import 'core/network/api_client.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
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
    return MaterialApp.router(
      // A new key rebuilds every screen, so all tr() texts switch to the new language at once.
      key: ValueKey(language),
      locale: Locale(language),
      supportedLocales: [for (final l in languages) Locale(l.code)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: 'Micro Bargain',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scaffoldMessengerKey: _messengerKey,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
