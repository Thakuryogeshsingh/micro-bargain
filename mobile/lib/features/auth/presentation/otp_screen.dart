import 'dart:async';

import 'package:flutter/foundation.dart';
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
    if (!kIsWeb) LocalNotifications.show('Micro Bargain OTP', tr('{0} आपका लॉगिन OTP है', [otp]));
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
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 4, 24, 24), children: [
        FadeSlideIn(
          child: Text(tr('OTP डालें'),
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2, color: AppTheme.ink)),
        ),
        const SizedBox(height: 8),
        FadeSlideIn(
          index: 1,
          child: Text(tr('+91 {0} पर भेजा गया 6 अंकों का कोड डालें', [widget.phone]),
              style: TextStyle(fontSize: 15, height: 1.4, color: AppTheme.muted)),
        ),
        const SizedBox(height: 28),
        FadeSlideIn(index: 2, child: _CodeBoxes(controller: _code, autofocus: widget.testOtp == null, onComplete: _verify)),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: _autoFilled
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    Icon(Icons.bolt_rounded, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(tr('टेस्ट मोड: OTP नोटिफ़िकेशन से अपने आप भर गया'),
                          style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 28),
        FadeSlideIn(
          index: 3,
          child: TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: tr('आपका नाम (नए यूज़र के लिए)'),
              prefixIcon: const Icon(Icons.person_outline_rounded),
              filled: true,
              fillColor: AppTheme.chip,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          index: 4,
          child: TextField(
            controller: _referral,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: tr('दोस्त का रेफ़रल कोड (अगर है)'),
              prefixIcon: const Icon(Icons.card_giftcard_rounded),
              filled: true,
              fillColor: AppTheme.chip,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 24),
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

/// Six digit boxes over one invisible text field (so paste and keyboard autofill still work).
class _CodeBoxes extends StatefulWidget {
  const _CodeBoxes({required this.controller, required this.autofocus, required this.onComplete});

  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback onComplete;

  @override
  State<_CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<_CodeBoxes> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(children: [
        Opacity(
          opacity: 0,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: ''),
            onChanged: (value) {
              if (value.length == 6) widget.onComplete();
            },
          ),
        ),
        Row(children: [
          for (var i = 0; i < 6; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.chip,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    width: 2,
                    color: _focus.hasFocus && i == code.length.clamp(0, 5)
                        ? AppTheme.ink
                        : i < code.length
                            ? (AppTheme.minimal ? AppTheme.accent : AppTheme.primary)
                            : Colors.transparent,
                  ),
                ),
                child: Text(i < code.length ? code[i] : '',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.ink)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}
