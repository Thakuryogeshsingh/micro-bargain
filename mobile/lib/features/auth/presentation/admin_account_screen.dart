import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';

/// Admin work happens only in the web admin panel. If the admin's number logs into the app,
/// it just says so and offers to log out.
class AdminAccountScreen extends ConsumerWidget {
  const AdminAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.admin_panel_settings_rounded, size: 72, color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(tr('यह एडमिन अकाउंट है'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${tr('दुकानें अप्रूव करना, रिपोर्ट और सेटिंग्स वेब एडमिन पैनल में हैं।')}\n'
              '${tr('ग्राहक या दुकानदार की तरह ऐप देखने के लिए किसी दूसरे नंबर से लॉगिन करें।')}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              child: Text(tr('लॉग आउट (दूसरे नंबर से लॉगिन)')),
            ),
          ]),
        ),
      ),
    );
  }
}
