import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/common.dart';

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
      showMessage(context, 'सही 10 अंकों का मोबाइल नंबर डालें');
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(context, () => ref.read(apiProvider).post('/auth/send-otp/', {'phone': phone}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.push('/otp', extra: phone);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 40),
          Icon(Icons.storefront, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Micro Bargain', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('पास की दुकानों की ताज़ा डील, सस्ते दाम पर', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 40),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'मोबाइल नंबर', prefixText: '+91 '),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('OTP भेजें'),
          ),
          const SizedBox(height: 16),
          Text('दुकानदार भी इसी नंबर से लॉगिन करें। लॉगिन के बाद "अपनी दुकान जोड़ें" चुनें।',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
