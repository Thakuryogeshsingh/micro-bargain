import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';

/// "Done!" screen after placing an order or reservation: an animated tick, then on to its details.
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key, required this.detailRoute, required this.isOrder});

  final String detailRoute;
  final bool isOrder;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.elasticOut));
    final fade = CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1, curve: Curves.easeOut));
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const Spacer(),
            ScaleTransition(
              scale: pop,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 4)],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 84),
              ),
            ),
            const SizedBox(height: 32),
            FadeTransition(
              opacity: fade,
              child: Column(children: [
                Text(widget.isOrder ? tr('ऑर्डर हो गया!') : tr('रिज़र्व हो गया!'),
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.ink)),
                const SizedBox(height: 10),
                Text(
                  widget.isOrder
                      ? tr('दुकान आपका ऑर्डर तैयार करेगी। हर अपडेट की सूचना मिलेगी।')
                      : tr('सामान आपके लिए रखा गया है। दुकान पर पिकअप कोड बताएं।'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: AppTheme.muted, height: 1.4),
                ),
              ]),
            ),
            const Spacer(),
            FadeTransition(
              opacity: fade,
              child: Column(children: [
                FilledButton(onPressed: () => context.pushReplacement(widget.detailRoute), child: Text(tr('विवरण देखें'))),
                const SizedBox(height: 10),
                TextButton(onPressed: () => context.go('/customer'), child: Text(tr('होम पर जाएं'))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
