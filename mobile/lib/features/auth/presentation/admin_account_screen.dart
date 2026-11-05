import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/app_config.dart';

/// The platform admin's number has no customer or shop data; the admin works in the web panel.
class AdminAccountScreen extends ConsumerWidget {
  const AdminAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.admin_panel_settings, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('यह एडमिन अकाउंट है', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'दुकानें अप्रूव करना, रिपोर्ट और सेटिंग्स वेब एडमिन पैनल में हैं।\n'
              'ग्राहक या दुकानदार की तरह ऐप देखने के लिए किसी दूसरे नंबर से लॉगिन करें।',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse('${AppConfig.siteUrl}/admin/dashboard/'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('एडमिन पैनल खोलें'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              child: const Text('लॉग आउट (दूसरे नंबर से लॉगिन)'),
            ),
          ]),
        ),
      ),
    );
  }
}
