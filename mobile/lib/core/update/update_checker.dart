import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n.dart';
import '../network/api_client.dart';
import '../theme/app_theme.dart';

/// Asks the server whether a newer app version exists and, if so, offers it. The APK opens in the browser,
/// which downloads it; Android then asks to install. A forced update cannot be dismissed.
class UpdateChecker {
  static bool _checked = false;

  static Future<void> check(BuildContext context, ApiClient api) async {
    if (_checked) return; // once per app start
    _checked = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final data = Map<String, dynamic>.from(await api.get('/app/latest/', query: {
        'platform': 'android',
        'current': info.buildNumber,
      }));
      if (data['update_available'] != true || !context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: data['force'] != true,
        builder: (_) => PopScope(canPop: data['force'] != true, child: _UpdateDialog(data: data)),
      );
    } catch (_) {
      // No network or no release published: never block the app for this.
    }
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final force = data['force'] == true;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(gradient: AppTheme.heroGradient),
          child: Column(children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 56),
            ),
            const SizedBox(height: 8),
            Text(tr('नया अपडेट उपलब्ध है'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(tr('वर्ज़न {0}', [data['version_name']]), style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
          ]),
        ),
        if ((data['notes'] as String? ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Text(data['notes'])),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(data['apk_url']), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_rounded),
              label: Text(tr('अपडेट करें')),
            ),
            if (!force) TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('बाद में'))),
          ]),
        ),
      ]),
    );
  }
}
