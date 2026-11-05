import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Fades and slides its child up into place. Items in a list pass their [index] to appear one after another.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 0.08});

  final Widget child;
  final int index;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Stagger the first screenful only; items further down the list appear as they scroll in.
    _timer = Timer(Duration(milliseconds: 45 * widget.index.clamp(0, 8)), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: Offset(0, widget.offset), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Shrinks slightly while pressed, like a physical button, with a light haptic tap.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) => setState(() => _down = down);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Animated grey placeholder used while content loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final x = rect.width * (_controller.value * 2 - 0.5);
          return LinearGradient(
            colors: [AppTheme.chip, AppTheme.card, AppTheme.chip],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromLTWH(x - rect.width / 2, 0, rect.width, rect.height));
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// A grey rounded block for skeleton layouts.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: AppTheme.chip, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Skeleton list shaped like deal cards.
class DealListSkeleton extends StatelessWidget {
  const DealListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(18)),
              child: const Row(children: [
                SkeletonBox(width: 104, height: 104, radius: 14),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SkeletonBox(width: 140, height: 16),
                    SizedBox(height: 10),
                    SkeletonBox(width: 100),
                    SizedBox(height: 10),
                    SkeletonBox(width: 160),
                    SizedBox(height: 10),
                    SkeletonBox(width: 90, height: 22, radius: 11),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Counts up to a number when it first appears (for dashboard figures).
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.format, this.style});

  final double value;
  final String Function(double) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(format(v), style: style),
    );
  }
}
