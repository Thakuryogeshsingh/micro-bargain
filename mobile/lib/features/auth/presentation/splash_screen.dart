import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Shown while the saved session is checked: logo gently pulsing on the brand gradient.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100), lowerBound: 0.92, upperBound: 1.05)
        ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.heroGradient),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: _pulse,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(32), boxShadow: AppTheme.softShadow(0.3)),
              child: Icon(Icons.storefront_rounded, size: 64, color: AppTheme.primary),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Micro Bargain', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 28),
          const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
        ]),
      ),
    );
  }
}
