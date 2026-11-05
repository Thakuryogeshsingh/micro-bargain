import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/brand.dart';

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
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(scale: _pulse, child: const BrandMark(size: 96)),
          const SizedBox(height: 22),
          const Wordmark(size: 30),
          const SizedBox(height: 28),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: AppTheme.chip,
                color: AppTheme.minimal ? AppTheme.accent : AppTheme.primary,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
