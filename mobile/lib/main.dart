import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'core/i18n/i18n.dart';
import 'core/network/api_client.dart';
import 'core/push/local_notifications.dart';
import 'core/push/push_service.dart';
import 'core/storage/prefs.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    try {
      await Prefs.init();
    } catch (_) {
      // Without saved settings the app still works; it just asks for the language again.
    }
    await PushService.init();
    await LocalNotifications.init();
    final container = ProviderContainer(retry: _retry);
    // Saved language, theme and onboarding state before the first frame.
    await container.read(languageProvider.notifier).restore();
    await container.read(themeProvider.notifier).restore();
    await container.read(onboardedProvider.notifier).restore();
    runApp(UncontrolledProviderScope(container: container, child: const MicroBargainApp()));
  } catch (error, stack) {
    // Show why start-up failed (with a way to send it) instead of a blank screen.
    runApp(_StartupError('$error\n\n$stack'));
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError(this.details);

  final String details;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('ऐप शुरू नहीं हो पाया 😔', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent('Micro Bargain start error:\n$details')}'),
                  mode: LaunchMode.externalApplication),
              child: const Text('शेयर करें (WhatsApp)'),
            ),
            const SizedBox(height: 12),
            SelectableText(details, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

/// Retry failed loads only for network trouble (3 times). Server answers such as 403/404 will not
/// change by asking again, so the screen shows the error with its own retry button instead.
Duration? _retry(int retryCount, Object error) {
  if (error is ApiException && error.code == 'network' && retryCount < 3) {
    return Duration(seconds: 2 << retryCount);
  }
  return null;
}
