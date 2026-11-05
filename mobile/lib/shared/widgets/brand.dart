import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The app's mark: a price tag in a rounded square (neon on the Fresh theme, brand colour otherwise).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final minimal = AppTheme.minimal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: minimal ? AppTheme.accent : AppTheme.primary,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(Icons.sell_rounded, size: size * 0.56, color: minimal ? Colors.black : Colors.white),
    );
  }
}

/// "micro bargain." in heavy lowercase with an accent full stop.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'micro bargain'),
        TextSpan(text: '.', style: TextStyle(color: AppTheme.minimal ? const Color(0xFF00C853) : AppTheme.accent)),
      ]),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -0.04 * size, color: color ?? AppTheme.ink),
    );
  }
}

/// Mark + wordmark side by side.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        BrandMark(size: size),
        SizedBox(width: size * 0.3),
        Wordmark(size: size * 0.55),
      ]);
}
