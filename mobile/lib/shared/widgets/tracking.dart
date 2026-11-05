import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';

/// One step in an order's journey.
class TrackStep {
  const TrackStep(this.icon, this.title, {this.at, this.done = false});

  final IconData icon;
  final String title;
  final DateTime? at;
  final bool done;
}

/// Vertical Zomato-style progress: finished steps are filled, the current one pulses.
class TrackingTimeline extends StatefulWidget {
  const TrackingTimeline({super.key, required this.steps, this.failed = false, this.failedText = ''});

  final List<TrackStep> steps;
  final bool failed;
  final String failedText;

  @override
  State<TrackingTimeline> createState() => _TrackingTimelineState();
}

class _TrackingTimelineState extends State<TrackingTimeline> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900), lowerBound: 0.85, upperBound: 1.15)
        ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    final current = steps.indexWhere((s) => !s.done);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: AppTheme.radius, boxShadow: AppTheme.softShadow(0.05)),
      child: widget.failed
          ? Row(children: [
              const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.failedText, style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink))),
            ])
          : Column(children: [
              for (var i = 0; i < steps.length; i++)
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Column(children: [
                      ScaleTransition(
                        scale: i == current ? _pulse : const AlwaysStoppedAnimation(1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: steps[i].done
                                ? AppTheme.primary
                                : i == current
                                    ? AppTheme.accent
                                    : AppTheme.chip,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(steps[i].done ? Icons.check_rounded : steps[i].icon,
                              size: 18, color: steps[i].done || i == current ? Colors.white : AppTheme.muted),
                        ),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            width: 3,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: steps[i].done ? AppTheme.primary : AppTheme.chip,
                          ),
                        ),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 18),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(steps[i].title,
                              style: TextStyle(
                                fontWeight: i == current || steps[i].done ? FontWeight.w800 : FontWeight.w500,
                                color: steps[i].done || i == current ? AppTheme.ink : AppTheme.muted,
                              )),
                          if (steps[i].at != null)
                            Text(timeOnly(steps[i].at!), style: TextStyle(fontSize: 12, color: AppTheme.muted)),
                          if (i == current) Text(tr('अभी यहाँ'), style: TextStyle(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                ),
            ]),
    );
  }
}

/// Calls [onTick] every [every] while on screen, e.g. to refresh an order's status.
class AutoRefresh extends StatefulWidget {
  const AutoRefresh({super.key, required this.onTick, required this.child, this.every = const Duration(seconds: 20)});

  final VoidCallback onTick;
  final Widget child;
  final Duration every;

  @override
  State<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends State<AutoRefresh> {
  late final Timer _timer = Timer.periodic(widget.every, (_) => widget.onTick());

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
