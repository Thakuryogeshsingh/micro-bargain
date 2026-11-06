import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../core/auth/session.dart';
import '../../../shared/widgets/bill.dart';
import '../merchant_providers.dart';
import '../team/team_screen.dart';
import '../../../core/i18n/i18n.dart';

Future<String?> _askCode(BuildContext context) =>
    askText(context, tr('ग्राहक का 4 अंकों का कोड'), hint: '1234', keyboard: TextInputType.number, maxLength: 4);

class MerchantBookingsScreen extends ConsumerWidget {
  const MerchantBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('बुकिंग')),
          bottom: TabBar(tabs: [Tab(text: tr('रिज़र्वेशन (दुकान पर पेमेंट)')), Tab(text: tr('ऑर्डर'))]),
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
      final reason = await askText(context, tr('अस्वीकार करने का कारण'), hint: tr('जैसे: स्टॉक खत्म'));
      if (reason == null) return;
      body = {'reason': reason};
    }
    if (!context.mounted) return;
    final done = {'confirm': tr('कन्फर्म किया'), 'reject': tr('अस्वीकार किया'), 'complete': tr('पिकअप पूरा ✅')};
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
            ? ListView(children: [const SizedBox(height: 120), EmptyView(icon: Icons.bookmark_border, message: tr('अभी कोई रिज़र्वेशन नहीं'))])
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
                        if (r.isOpen)
                          Text(
                            r.pickupAt != null
                                ? tr('🕒 ग्राहक {0} पर आएगा', [timeOnly(r.pickupAt!)])
                                : tr('{0} तक पिकअप', [timeOnly(r.expiresAt)]),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        if (r.isOpen)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(spacing: 8, children: [
                              if (r.status == 'pending') FilledButton.tonal(onPressed: () => _act(context, ref, r, 'confirm'), child: Text(tr('कन्फर्म'))),
                              if (r.status == 'pending') OutlinedButton(onPressed: () => _act(context, ref, r, 'reject'), child: Text(tr('अस्वीकार'))),
                              if (r.status == 'confirmed')
                                FilledButton.icon(
                                  onPressed: () => _act(context, ref, r, 'complete'),
                                  icon: const Icon(Icons.pin),
                                  label: Text(tr('कोड डालकर पिकअप पूरा करें')),
                                ),
                            ]),
                          ),
                        if (r.status == 'completed' && r.billToken.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => shareBill(r.billToken, r.number, phone: r.customerPhone),
                            icon: const Icon(Icons.receipt_long_outlined, size: 18),
                            label: Text(tr('बिल WhatsApp पर भेजें')),
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
      final reason = await askText(context, tr('ऑर्डर रद्द करने का कारण'), hint: tr('जैसे: स्टॉक खत्म'));
      if (reason == null) return;
      body = {'reason': reason};
    }
    if (!context.mounted) return;
    final done = {'accept': tr('ऑर्डर स्वीकार किया'), 'ready': tr('ग्राहक को सूचना भेजी'), 'complete': tr('ऑर्डर पूरा ✅'), 'reject': tr('ऑर्डर रद्द किया')};
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
            return ListView(children: [const SizedBox(height: 120), EmptyView(icon: Icons.receipt_long, message: tr('अभी कोई ऑर्डर नहीं'))]);
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
                    Text('${o.isDelivery ? tr('🛵 डिलीवरी') : tr('🛍️ पिकअप')} · ${o.paymentMethod == 'online' ? tr('ऑनलाइन ({0})', [statusLabel(o.paymentStatus)]) : tr('कैश लेना है')}'),
                    for (final item in o.items) Text('• ${item.productName} — ${qty(item.quantity)} ${unitLabel(item.unit)}'),
                    if (o.isDelivery) Text(tr('पता: {0}', [o.deliveryAddress]), style: Theme.of(context).textTheme.bodySmall),
                    if (o.isDelivery && o.recipientName.isNotEmpty)
                      Text(tr('पाने वाले: {0} ({1})', [o.recipientName, o.recipientPhone]),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    Row(children: [
                      Text(o.customerName.isEmpty ? o.customerPhone : '${o.customerName} · ${o.customerPhone}',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (!o.customerPhone.contains('x'))
                        IconButton(icon: const Icon(Icons.call, size: 18), onPressed: () => launchUrl(Uri.parse('tel:${o.customerPhone}'))),
                    ]),
                    if (open)
                      Wrap(spacing: 8, children: [
                        if (o.status == 'pending') FilledButton.tonal(onPressed: () => _act(context, ref, o, 'accept'), child: Text(tr('स्वीकार'))),
                        if (o.status == 'confirmed')
                          FilledButton.tonal(
                            onPressed: () => _act(context, ref, o, 'ready'),
                            child: Text(o.isDelivery ? tr('डिलीवरी के लिए निकला') : tr('तैयार है')),
                          ),
                        if (o.status == 'ready' || o.status == 'out_for_delivery')
                          FilledButton.icon(onPressed: () => _act(context, ref, o, 'complete'), icon: const Icon(Icons.pin), label: Text(tr('कोड डालकर पूरा करें'))),
                        if (o.isDelivery && o.status == 'confirmed' && !isStaffUser(ref))
                          OutlinedButton.icon(
                            onPressed: () => assignDelivery(context, ref, o),
                            icon: const Icon(Icons.delivery_dining_rounded, size: 18),
                            label: Text(o.deliveryPartnerName.isEmpty ? tr('डिलीवरी वाले को दें') : tr('भेजा: {0}', [o.deliveryPartnerName])),
                          ),
                        OutlinedButton(onPressed: () => _act(context, ref, o, 'reject'), child: Text(tr('रद्द करें'))),
                      ]),
                    if (o.status == 'completed' && o.billToken.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => shareBill(o.billToken, o.number, phone: o.customerPhone),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: Text(tr('बिल WhatsApp पर भेजें')),
                      ),
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



/// Staff (helpers) see the same booking screen; only the owner hands deliveries out.
bool isStaffUser(WidgetRef ref) => ref.read(sessionProvider).isStaff;
