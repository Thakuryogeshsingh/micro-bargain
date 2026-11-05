import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
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
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
            FadeSlideIn(
              child: Column(children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: AppTheme.softShadow(0.25),
                    ),
                    child: const Icon(Icons.storefront_rounded, size: 52, color: AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Micro Bargain',
                    style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(hint,
                      key: ValueKey(role),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 15)),
                ),
              ]),
            ),
            const SizedBox(height: 28),
            FadeSlideIn(
              index: 2,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: AppTheme.softShadow(0.2),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(tr('आप कौन हैं?'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(children: [
                    for (final r in roles)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _RoleCard(
                            icon: r.icon,
                            label: r.label,
                            selected: role == r.key,
                            onTap: () => ref.read(loginRoleProvider.notifier).set(r.key),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 18, letterSpacing: 1.5, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: tr('मोबाइल नंबर'),
                      prefixText: '+91  ',
                      prefixIcon: const Icon(Icons.phone_iphone_rounded),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _busy
                          ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(tr('OTP भेजें')),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: selected ? AppTheme.heroGradient : null,
          color: selected ? null : const Color(0xFFF1F5F2),
          borderRadius: BorderRadius.circular(18),
          boxShadow: selected ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))] : null,
        ),
        child: Column(children: [
          Icon(icon, size: 28, color: selected ? Colors.white : AppTheme.primaryDark),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? Colors.white : AppTheme.ink)),
        ]),
      ),
    );
  }
}
