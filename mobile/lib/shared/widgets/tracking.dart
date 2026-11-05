import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

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

/// Delivery map: the shop, the delivery point and the route between them, with where the order is now.
class OrderMap extends StatelessWidget {
  const OrderMap({
    super.key,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.toLatitude,
    required this.toLongitude,
    required this.status,
  });

  final double shopLatitude;
  final double shopLongitude;
  final double toLatitude;
  final double toLongitude;
  final String status;

  @override
  Widget build(BuildContext context) {
    final shop = ll.LatLng(shopLatitude, shopLongitude);
    final home = ll.LatLng(toLatitude, toLongitude);
    final (label, icon) = switch (status) {
      'out_for_delivery' => (tr('रास्ते में है'), Icons.delivery_dining_rounded),
      'completed' => (tr('पहुंच गया'), Icons.home_rounded),
      'cancelled' || 'refunded' => (tr('रद्द'), Icons.block_rounded),
      _ => (tr('दुकान पर तैयार हो रहा है'), Icons.storefront_rounded),
    };
    return Container(
      height: 190,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow(0.06)),
      child: Stack(children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(bounds: LatLngBounds(shop, home), padding: const EdgeInsets.all(44)),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.microbargain.micro_bargain'),
            PolylineLayer(polylines: [
              Polyline(points: [shop, home], strokeWidth: 4, color: AppTheme.ink, pattern: StrokePattern.dashed(segments: const [10, 8])),
            ]),
            MarkerLayer(markers: [
              Marker(point: shop, width: 38, height: 38, child: _Pin(icon: Icons.storefront_rounded, color: AppTheme.ink)),
              Marker(
                point: home,
                width: 38,
                height: 38,
                child: _Pin(icon: Icons.home_rounded, color: AppTheme.minimal ? const Color(0xFF00C853) : AppTheme.primary),
              ),
            ]),
          ],
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      );
}
