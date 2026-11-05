import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/motion.dart';

/// Which kind of account the person said they are on the login screen. A customer account that logs in
/// as "shop owner" is taken straight to shop registration.
class LoginRoleController extends Notifier<String> {
  @override
  String build() => 'customer';

  void set(String role) => state = role;
}

final loginRoleProvider = NotifierProvider<LoginRoleController, String>(LoginRoleController.new);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  bool _busy = false;

  Future<void> _send() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      showMessage(context, tr('सही 10 अंकों का मोबाइल नंबर डालें'));
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    Map<String, dynamic>? response;
    final ok = await runAction(context, () async {
      response = Map<String, dynamic>.from(await ref.read(apiProvider).post('/auth/send-otp/', {'phone': phone}));
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.push('/otp', extra: {'phone': phone, 'otp': response?['test_otp']});
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(loginRoleProvider);
    final roles = [
      (key: 'customer', icon: Icons.shopping_bag_rounded, label: tr('ग्राहक')),
      (key: 'merchant', icon: Icons.storefront_rounded, label: tr('दुकानदार')),
    ];
    final hint = switch (role) {
      'merchant' => tr('अपनी दुकान की डील डालें और पास के ग्राहकों तक पहुंचें'),
      _ => tr('पास की दुकानों की ताज़ा डील, सस्ते दाम पर'),
    };

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 24), children: [
          const FadeSlideIn(child: Align(alignment: Alignment.centerLeft, child: BrandLockup(size: 40))),
          const SizedBox(height: 44),
          FadeSlideIn(
            index: 1,
            child: Text(tr('सबसे सस्ता,\nसबसे पास।'),
                style: TextStyle(fontSize: 40, height: 1.02, fontWeight: FontWeight.w900, letterSpacing: -1.6, color: AppTheme.ink)),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            index: 2,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(hint, key: ValueKey(role), style: TextStyle(color: AppTheme.muted, fontSize: 16, height: 1.4)),
            ),
          ),
          const SizedBox(height: 36),
          FadeSlideIn(
            index: 3,
            child: Text(tr('आप कौन हैं?'), style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            index: 3,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppTheme.chip, borderRadius: BorderRadius.circular(30)),
              child: Row(children: [
                for (final r in roles)
                  Expanded(
                    child: _RoleCard(
                      icon: r.icon,
                      label: r.label,
                      selected: role == r.key,
                      onTap: () => ref.read(loginRoleProvider.notifier).set(r.key),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          FadeSlideIn(
            index: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(color: AppTheme.chip, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Text('+91', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 14), color: AppTheme.muted.withValues(alpha: 0.3)),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.w800, color: AppTheme.ink),
                    decoration: InputDecoration(
                      hintText: tr('मोबाइल नंबर'),
                      hintStyle: TextStyle(fontSize: 17, letterSpacing: 0, fontWeight: FontWeight.w500, color: AppTheme.muted),
                      counterText: '',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          FadeSlideIn(
            index: 5,
            child: FilledButton(
              onPressed: _busy ? null : _send,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(tr('OTP भेजें')),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: selected ? (AppTheme.minimal ? AppTheme.accent : Colors.white) : AppTheme.muted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: selected ? AppTheme.background : AppTheme.ink)),
          ),
        ]),
      ),
    );
  }
}
