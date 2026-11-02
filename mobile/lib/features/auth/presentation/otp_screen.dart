import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/common.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      setState(() => _resendIn--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) return;
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    await runAction(context, () async {
      final response = Map<String, dynamic>.from(
          await api.post('/auth/verify-otp/', {'phone': widget.phone, 'code': _code.text}));
      final session = ref.read(sessionProvider.notifier);
      await session.signIn(response);
      if (response['is_new_user'] == true && _name.text.trim().isNotEmpty) {
        await api.patch('/auth/profile/update/', {'name': _name.text.trim()});
        await session.reloadUser();
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _resend() async {
    final ok = await runAction(context, () => ref.read(apiProvider).post('/auth/send-otp/', {'phone': widget.phone}),
        success: 'OTP फिर से भेजा गया');
    if (ok) _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OTP डालें')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text('+91 ${widget.phone} पर भेजा गया 6 अंकों का कोड डालें'),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 12),
          onChanged: (value) {
            if (value.length == 6) _verify();
          },
        ),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'आपका नाम (नए यूज़र के लिए)'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _verify, child: const Text('लॉगिन करें')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resendIn > 0 ? null : _resend,
          child: Text(_resendIn > 0 ? '$_resendIn सेकंड में दोबारा भेजें' : 'OTP दोबारा भेजें'),
        ),
      ]),
    );
  }
}
