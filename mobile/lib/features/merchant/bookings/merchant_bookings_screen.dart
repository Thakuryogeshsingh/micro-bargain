import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../merchant_providers.dart';

Future<String?> _askCode(BuildContext context) =>
    askText(context, 'ग्राहक का 4 अंकों का कोड', hint: '1234', keyboard: TextInputType.number, maxLength: 4);

class MerchantBookingsScreen extends ConsumerWidget {
  const MerchantBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('बुकिंग'),
          bottom: const TabBar(tabs: [Tab(text: 'रिज़र्वेशन (दुकान पर पेमेंट)'), Tab(text: 'ऑर्डर')]),
        ),
        body: const TabBarView(children: [_ReservationsTab(), _OrdersTab()]),
      ),
    );
  }
}

class _ReservationsTab extends ConsumerWidget {
  const _ReservationsTab();

  Future<void> _act(BuildContext context, WidgetRef ref, Reservation r, String action) async {
    final api = ref.read(apiProvider);
    Object body = {};
    if (action == 'complete') {
      final code = await _askCode(context);
      if (code == null || code.isEmpty) return;
      body = {'pickup_code': code};
    } else if (action == 'reject') {
      final reason = await askText(context, 'अस्वीकार करने का कारण', hint: 'जैसे: स्टॉक खत्म');
      if (reason == null) return;
      body = {'reason': reason};
    }
    if (!context.mounted) return;
    const done = {'confirm': 'कन्फर्म किया', 'reject': 'अस्वीकार किया', 'complete': 'पिकअप पूरा ✅'};
    if (await runAction(context, () => api.post('/reservations/${r.id}/$action/', body), success: done[action])) {
      ref.invalidate(merchantReservationsProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(merchantReservationsProvider.future),
      child: AsyncView(
        value: ref.watch(merchantReservationsProvider),
        onRetry: () => ref.invalidate(merchantReservationsProvider),
        data: (items) => items.isEmpty
            ? ListView(children: const [SizedBox(height: 120), EmptyView(icon: Icons.bookmark_border, message: 'अभी कोई रिज़र्वेशन नहीं')])
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final r = items[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text('${r.productName} · ${qty(r.quantity)} ${unitLabel(r.unit)}',
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          StatusChip(r.status),
                        ]),
                        Text('${r.number} · ${rupees(r.total)} · ${r.customerName.isEmpty ? r.customerPhone : r.customerName}'),
                        if (r.isOpen) Text('${timeOnly(r.expiresAt)} तक पिकअप', style: Theme.of(context).textTheme.bodySmall),
                        if (r.isOpen)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(spacing: 8, children: [
                              if (r.status == 'pending') FilledButton.tonal(onPressed: () => _act(context, ref, r, 'confirm'), child: const Text('कन्फर्म')),
                              if (r.status == 'pending') OutlinedButton(onPressed: () => _act(context, ref, r, 'reject'), child: const Text('अस्वीकार')),
                              if (r.status == 'confirmed')
                                FilledButton.icon(
                                  onPressed: () => _act(context, ref, r, 'complete'),
                                  icon: const Icon(Icons.pin),
                                  label: const Text('कोड डालकर पिकअप पूरा करें'),
                                ),
                            ]),
                          ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab();

  Future<void> _act(BuildContext context, WidgetRef ref, Order o, String action) async {
    final api = ref.read(apiProvider);
    Object body = {};
    if (action == 'complete') {
      final code = await _askCode(context);
      if (code == null || code.isEmpty) return;
      body = {'pickup_code': code};
    } else if (action == 'reject') {
      final reason = await askText(context, 'ऑर्डर रद्द करने का कारण', hint: 'जैसे: स्टॉक खत्म');
      if (reason == null) return;
      body = {'reason': reason};
    }
    if (!context.mounted) return;
    const done = {'accept': 'ऑर्डर स्वीकार किया', 'ready': 'ग्राहक को सूचना भेजी', 'complete': 'ऑर्डर पूरा ✅', 'reject': 'ऑर्डर रद्द किया'};
    if (await runAction(context, () => api.post('/orders/${o.id}/$action/', body), success: done[action])) {
      ref.invalidate(merchantOrdersProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(merchantOrdersProvider.future),
      child: AsyncView(
        value: ref.watch(merchantOrdersProvider),
        onRetry: () => ref.invalidate(merchantOrdersProvider),
        data: (items) {
          final visible = items.where((o) => o.status != 'pending_payment').toList();
          if (visible.isEmpty) {
            return ListView(children: const [SizedBox(height: 120), EmptyView(icon: Icons.receipt_long, message: 'अभी कोई ऑर्डर नहीं')]);
          }
          return ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final o = visible[i];
              final open = ['pending', 'confirmed', 'ready', 'out_for_delivery'].contains(o.status);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${o.number} · ${rupees(o.total)}', style: Theme.of(context).textTheme.titleMedium)),
                      StatusChip(o.status),
                    ]),
                    Text('${o.isDelivery ? '🛵 डिलीवरी' : '🛍️ पिकअप'} · ${o.paymentMethod == 'online' ? 'ऑनलाइन (${statusLabel(o.paymentStatus)})' : 'कैश लेना है'}'),
                    for (final item in o.items) Text('• ${item.productName} — ${qty(item.quantity)} ${unitLabel(item.unit)}'),
                    if (o.isDelivery) Text('पता: ${o.deliveryAddress}', style: Theme.of(context).textTheme.bodySmall),
                    Row(children: [
                      Text(o.customerName.isEmpty ? o.customerPhone : '${o.customerName} · ${o.customerPhone}',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (!o.customerPhone.contains('x'))
                        IconButton(icon: const Icon(Icons.call, size: 18), onPressed: () => launchUrl(Uri.parse('tel:${o.customerPhone}'))),
                    ]),
                    if (open)
                      Wrap(spacing: 8, children: [
                        if (o.status == 'pending') FilledButton.tonal(onPressed: () => _act(context, ref, o, 'accept'), child: const Text('स्वीकार')),
                        if (o.status == 'confirmed')
                          FilledButton.tonal(
                            onPressed: () => _act(context, ref, o, 'ready'),
                            child: Text(o.isDelivery ? 'डिलीवरी के लिए निकला' : 'तैयार है'),
                          ),
                        if (o.status == 'ready' || o.status == 'out_for_delivery')
                          FilledButton.icon(onPressed: () => _act(context, ref, o, 'complete'), icon: const Icon(Icons.pin), label: const Text('कोड डालकर पूरा करें')),
                        OutlinedButton(onPressed: () => _act(context, ref, o, 'reject'), child: const Text('रद्द करें')),
                      ]),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

