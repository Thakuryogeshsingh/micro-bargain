import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';
import '../merchant_providers.dart';

/// Everything waiting for the shop's answer: new orders and new reservations.
class PendingWork {
  const PendingWork(this.orders, this.reservations);

  final List<Order> orders;
  final List<Reservation> reservations;

  Set<String> get ids => {for (final o in orders) 'o${o.id}', for (final r in reservations) 'r${r.id}'};
  bool get isEmpty => orders.isEmpty && reservations.isEmpty;
}

Future<PendingWork> fetchPending(ApiClient api) async {
  final orders = await api.list('/orders/', query: {'status': 'pending'});
  final reservations = await api.list('/reservations/', query: {'status': 'pending'});
  return PendingWork(
    [for (final o in orders) Order.fromJson(o)],
    [for (final r in reservations) Reservation.fromJson(r)],
  );
}

/// Checks for new orders every 15 seconds while the merchant app is open and opens the ringing alert screen.
class OrderAlertWatcher {
  OrderAlertWatcher(this._context, this._api);

  final BuildContext _context;
  final ApiClient _api;
  final Set<String> _seen = {};
  Timer? _timer;
  bool _alertOpen = false;

  void start() {
    check();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => check());
  }

  void dispose() => _timer?.cancel();

  Future<void> check() async {
    if (_alertOpen) return;
    try {
      final pending = await fetchPending(_api);
      final fresh = pending.ids.difference(_seen);
      _seen.addAll(pending.ids);
      if (fresh.isEmpty || !_context.mounted) return;
      _alertOpen = true;
      await _context.push('/merchant/incoming');
      _alertOpen = false;
    } catch (_) {
      // Offline for a moment: try again on the next tick.
    }
  }
}

/// Full-screen "new order" alert: rings and vibrates until every request is answered or it is closed.
class IncomingOrdersScreen extends ConsumerStatefulWidget {
  const IncomingOrdersScreen({super.key});

  @override
  ConsumerState<IncomingOrdersScreen> createState() => _IncomingOrdersScreenState();
}

class _IncomingOrdersScreenState extends ConsumerState<IncomingOrdersScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
  Timer? _buzz;
  PendingWork? _work;
  bool _ringing = false;

  @override
  void initState() {
    super.initState();
    _startRing();
    _load();
  }

  void _startRing() {
    _ringing = true;
    FlutterRingtonePlayer().playRingtone(looping: true, volume: 1.0, asAlarm: false);
    _buzz = Timer.periodic(const Duration(milliseconds: 1200), (_) => HapticFeedback.heavyImpact());
  }

  void _stopRing() {
    if (!_ringing) return;
    _ringing = false;
    FlutterRingtonePlayer().stop();
    _buzz?.cancel();
    _shake.stop();
  }

  Future<void> _load() async {
    final work = await fetchPending(ref.read(apiProvider));
    if (!mounted) return;
    setState(() => _work = work);
    if (work.isEmpty) _close();
  }

  void _close() {
    _stopRing();
    ref.invalidate(dashboardProvider);
    ref.invalidate(merchantOrdersProvider);
    ref.invalidate(merchantReservationsProvider);
    if (mounted && context.canPop()) context.pop();
  }

  Future<void> _act(String path, [Object body = const {}]) async {
    _stopRing();
    if (await runAction(context, () => ref.read(apiProvider).post(path, body))) await _load();
  }

  Future<void> _reject(String path) async {
    _stopRing();
    final reason = await askText(context, tr('अस्वीकार करने का कारण'), hint: tr('जैसे: स्टॉक खत्म'));
    if (reason == null || !mounted) return;
    await _act(path, {'reason': reason});
  }

  @override
  void dispose() {
    _stopRing();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final work = _work;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _stopRing(),
      child: Scaffold(
        backgroundColor: AppTheme.primaryDark,
        body: SafeArea(
          child: Column(children: [
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _shake,
              builder: (_, child) => Transform.rotate(angle: (_shake.value - 0.5) * 0.5, child: child),
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  gradient: AppTheme.dealGradient,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppTheme.deal.withValues(alpha: 0.6), blurRadius: 40, spreadRadius: 6)],
                ),
                child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 60),
              ),
            ),
            const SizedBox(height: 18),
            Text(tr('नया ऑर्डर आया! 🎉'),
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(tr('जल्दी स्वीकार करें, ग्राहक इंतज़ार कर रहा है'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: work == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(padding: const EdgeInsets.fromLTRB(14, 18, 14, 14), children: [
                        for (var i = 0; i < work.orders.length; i++)
                          FadeSlideIn(
                            index: i,
                            child: _RequestCard(
                              icon: work.orders[i].isDelivery ? Icons.delivery_dining_rounded : Icons.shopping_bag_rounded,
                              title: '${work.orders[i].number} · ${rupees(work.orders[i].total)}',
                              lines: [
                                for (final item in work.orders[i].items)
                                  '${item.productName} — ${qty(item.quantity)} ${unitLabel(item.unit)}',
                                work.orders[i].isDelivery ? '🛵 ${tr('डिलीवरी')}' : '🛍️ ${tr('पिकअप')}',
                              ],
                              onAccept: () => _act('/orders/${work.orders[i].id}/accept/'),
                              onReject: () => _reject('/orders/${work.orders[i].id}/reject/'),
                            ),
                          ),
                        for (var i = 0; i < work.reservations.length; i++)
                          FadeSlideIn(
                            index: work.orders.length + i,
                            child: _RequestCard(
                              icon: Icons.bookmark_added_rounded,
                              title: '${work.reservations[i].number} · ${rupees(work.reservations[i].total)}',
                              lines: [
                                '${work.reservations[i].productName} — ${qty(work.reservations[i].quantity)} ${unitLabel(work.reservations[i].unit)}',
                                if (work.reservations[i].pickupAt != null)
                                  tr('🕒 ग्राहक {0} पर आएगा', [timeOnly(work.reservations[i].pickupAt!)]),
                              ],
                              onAccept: () => _act('/reservations/${work.reservations[i].id}/confirm/'),
                              onReject: () => _reject('/reservations/${work.reservations[i].id}/reject/'),
                            ),
                          ),
                      ]),
              ),
            ),
            Container(
              color: AppTheme.background,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _close,
                icon: const Icon(Icons.volume_off_rounded),
                label: Text(tr('बंद करें')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.icon, required this.title, required this.lines, required this.onAccept, required this.onReject});

  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: AppTheme.radius, boxShadow: AppTheme.softShadow(0.08)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: AppTheme.primary.withValues(alpha: 0.12), child: Icon(icon, color: AppTheme.primary)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.ink))),
        ]),
        const SizedBox(height: 8),
        for (final line in lines) Text('• $line', style: TextStyle(color: AppTheme.ink)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: const Color(0xFFDC2626)),
              onPressed: onReject,
              child: Text(tr('अस्वीकार')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: const Color(0xFF16A34A)),
              onPressed: onAccept,
              icon: const Icon(Icons.check_rounded),
              label: Text(tr('स्वीकार करें')),
            ),
          ),
        ]),
      ]),
    );
  }
}
