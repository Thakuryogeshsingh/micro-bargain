import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/push/local_notifications.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone, this.testOtp});

  final String phone;

  /// Sent by a test server (no real SMS yet): shown as a notification and filled in automatically.
  final String? testOtp;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _referral = TextEditingController();
  bool _busy = false;
  bool _autoFilled = false;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _deliverTestOtp(widget.testOtp);
  }

  void _deliverTestOtp(String? otp) {
    if (otp == null) return;
    LocalNotifications.show('Micro Bargain OTP', tr('{0} आपका लॉगिन OTP है', [otp]));
    // Fill it in shortly after, so the person sees the notification arrive first.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _code.text = otp;
        _autoFilled = true;
      });
    });
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
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    await runAction(context, () async {
      final response = Map<String, dynamic>.from(await api.post('/auth/verify-otp/', {
        'phone': widget.phone,
        'code': _code.text,
        if (_referral.text.trim().isNotEmpty) 'referral_code': _referral.text.trim(),
      }));
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
    Map<String, dynamic>? response;
    final ok = await runAction(context, () async {
      response = Map<String, dynamic>.from(await ref.read(apiProvider).post('/auth/send-otp/', {'phone': widget.phone}));
    }, success: tr('OTP फिर से भेजा गया'));
    if (ok) {
      _startTimer();
      _deliverTestOtp(response?['test_otp']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('OTP डालें'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        FadeSlideIn(
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.sms_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(tr('+91 {0} पर भेजा गया 6 अंकों का कोड डालें', [widget.phone]))),
          ]),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          index: 1,
          child: TextField(
            controller: _code,
            autofocus: widget.testOtp == null,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, letterSpacing: 14, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            onChanged: (value) {
              if (value.length == 6) _verify();
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: _autoFilled
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.notifications_active_rounded, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(tr('टेस्ट मोड: OTP नोटिफ़िकेशन से अपने आप भर गया'),
                          style: const TextStyle(color: AppTheme.primaryDark, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 2,
          child: TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('आपका नाम (नए यूज़र के लिए)'), prefixIcon: const Icon(Icons.person_rounded)),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          index: 3,
          child: TextField(
            controller: _referral,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: tr('दोस्त का रेफ़रल कोड (अगर है)'),
              prefixIcon: const Icon(Icons.card_giftcard_rounded),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(tr('लॉगिन करें')),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resendIn > 0 ? null : _resend,
          child: Text(_resendIn > 0 ? tr('{0} सेकंड में दोबारा भेजें', [_resendIn]) : tr('OTP दोबारा भेजें')),
        ),
      ]),
    );
  }
}
