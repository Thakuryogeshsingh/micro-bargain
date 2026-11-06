import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/tracking.dart';
import '../customer/profile/profile_screens.dart';
import '../merchant/alerts/order_alerts.dart';
import '../merchant/bookings/merchant_bookings_screen.dart';

final myJobProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final data = Map<String, dynamic>.from(await ref.watch(apiProvider).get('/team/me/'));
  return data['job'] == null ? null : Map<String, dynamic>.from(data['job']);
});

/// Home for shop staff: helpers get the shop's bookings, delivery people get their deliveries.
class StaffShell extends ConsumerWidget {
  const StaffShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(myJobProvider),
      onRetry: () => ref.invalidate(myJobProvider),
      data: (job) {
        if (job == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Micro Bargain')),
            body: EmptyView(
              icon: Icons.work_off_outlined,
              message: tr('आप अभी किसी दुकान की टीम में नहीं हैं।'),
              action: FilledButton(onPressed: () => logout(context, ref), child: Text(tr('लॉग आउट'))),
            ),
          );
        }
        return job['kind'] == 'delivery' ? DeliveryScreen(job: job) : _HelperHome(job: job);
      },
    );
  }
}

class _HelperHome extends ConsumerStatefulWidget {
  const _HelperHome({required this.job});

  final Map<String, dynamic> job;

  @override
  ConsumerState<_HelperHome> createState() => _HelperHomeState();
}

class _HelperHomeState extends ConsumerState<_HelperHome> {
  OrderAlertWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _watcher = OrderAlertWatcher(context, ref.read(apiProvider))..start();
    });
  }

  @override
  void dispose() {
    _watcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const MerchantBookingsScreen(),
      bottomNavigationBar: SafeArea(
        child: ListTile(
          leading: const Icon(Icons.storefront_rounded),
          title: Text(widget.job['shop_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(tr('हेल्पर · {0}', [ref.watch(sessionProvider).user?.displayName ?? ''])),
          trailing: TextButton(onPressed: () => logout(context, ref), child: Text(tr('लॉग आउट'))),
        ),
      ),
    );
  }
}

final _myDeliveriesProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  return [for (final o in await ref.watch(apiProvider).list('/orders/')) Order.fromJson(o)];
});

/// Delivery person: assigned orders, share live location, finish with the customer's code.
class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key, required this.job});

  final Map<String, dynamic> job;

  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  Timer? _tracker;
  int? _trackingOrder;

  @override
  void dispose() {
    _tracker?.cancel();
    super.dispose();
  }

  Future<void> _sendLocation(int orderId) async {
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)));
      await ref.read(apiProvider).post('/orders/$orderId/location/', {
        'latitude': p.latitude.toStringAsFixed(6),
        'longitude': p.longitude.toStringAsFixed(6),
      });
    } catch (_) {
      // Weak GPS or network: the next tick tries again.
    }
  }

  Future<void> _toggleTracking(Order o) async {
    if (_trackingOrder == o.id) {
      _tracker?.cancel();
      setState(() => _trackingOrder = null);
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (!mounted) return;
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      showMessage(context, tr('लोकेशन की अनुमति दें, तभी ग्राहक आपको मैप पर देख पाएंगे'), error: true);
      return;
    }
    _tracker?.cancel();
    setState(() => _trackingOrder = o.id);
    _sendLocation(o.id);
    _tracker = Timer.periodic(const Duration(seconds: 15), (_) => _sendLocation(o.id));
  }

  Future<void> _complete(Order o) async {
    final code = await askText(context, tr('ग्राहक से 4 अंकों का कोड पूछें'), keyboard: TextInputType.number, maxLength: 4, icon: Icons.pin_outlined);
    if (code == null || !mounted) return;
    final ok = await runAction(context, () => ref.read(apiProvider).post('/orders/${o.id}/complete/', {'pickup_code': code}),
        success: tr('डिलीवरी पूरी ✅'));
    if (ok) {
      if (_trackingOrder == o.id) {
        _tracker?.cancel();
        _trackingOrder = null;
      }
      ref.invalidate(_myDeliveriesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('मेरी डिलीवरी')),
        actions: [TextButton(onPressed: () => logout(context, ref), child: Text(tr('लॉग आउट')))],
      ),
      body: AsyncView(
        value: ref.watch(_myDeliveriesProvider),
        onRetry: () => ref.invalidate(_myDeliveriesProvider),
        data: (orders) {
          final open = orders.where((o) => ['confirmed', 'ready', 'out_for_delivery'].contains(o.status)).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_myDeliveriesProvider.future),
            child: open.isEmpty
                ? ListView(children: [
                    EmptyView(icon: Icons.delivery_dining_outlined, message: tr('अभी कोई डिलीवरी नहीं।\n{0} से नई डिलीवरी आने पर सूचना मिलेगी।', [widget.job['shop_name']])),
                  ])
                : ListView(padding: const EdgeInsets.all(16), children: [
                    for (final o in open)
                      Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (o.deliveryLatitude != null)
                            OrderMap(
                              shopLatitude: o.shopLatitude,
                              shopLongitude: o.shopLongitude,
                              toLatitude: o.deliveryLatitude!,
                              toLongitude: o.deliveryLongitude!,
                              status: o.status,
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${o.number} · ${rupees(o.total)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              Text(o.paymentMethod == 'online' ? tr('ऑनलाइन पेमेंट हो चुका') : tr('कैश लेना है: {0}', [rupees(o.total)]),
                                  style: TextStyle(color: o.paymentMethod == 'online' ? const Color(0xFF15803D) : const Color(0xFFD97706), fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(o.deliveryAddress),
                              if (o.recipientName.isNotEmpty) Text(tr('पाने वाले: {0} ({1})', [o.recipientName, o.recipientPhone])),
                              const SizedBox(height: 10),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton.icon(
                                  onPressed: () => launchUrl(Uri.parse('tel:${o.recipientPhone.isNotEmpty ? o.recipientPhone : o.customerPhone}')),
                                  icon: const Icon(Icons.call_outlined, size: 18),
                                  label: Text(tr('कॉल')),
                                ),
                                if (o.deliveryLatitude != null)
                                  OutlinedButton.icon(
                                    onPressed: () => launchUrl(
                                      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${o.deliveryLatitude},${o.deliveryLongitude}'),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    icon: const Icon(Icons.directions_rounded, size: 18),
                                    label: Text(tr('रास्ता')),
                                  ),
                                FilledButton.tonalIcon(
                                  onPressed: () => _toggleTracking(o),
                                  icon: Icon(_trackingOrder == o.id ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded, size: 18),
                                  label: Text(_trackingOrder == o.id ? tr('लोकेशन चालू ✓') : tr('लाइव लोकेशन चालू करें')),
                                ),
                                if (o.status == 'out_for_delivery' || o.status == 'ready')
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AppTheme.ink),
                                    onPressed: () => _complete(o),
                                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                    label: Text(tr('कोड डालकर पूरा करें')),
                                  ),
                              ]),
                            ]),
                          ),
                        ]),
                      ),
                  ]),
          );
        },
      ),
    );
  }
}
