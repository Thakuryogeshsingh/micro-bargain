import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/payments/checkout.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../customer_providers.dart';
import '../reviews/review_sheet.dart';
import '../../../core/i18n/i18n.dart';

/// Big code the customer shows or tells at the shop / to the delivery person.
class PickupCodeCard extends StatelessWidget {
  const PickupCodeCard({super.key, required this.code, required this.hint});

  final String code;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text(hint, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(code, style: TextStyle(fontSize: 44, letterSpacing: 14, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
        ]),
      ),
    );
  }
}

Widget _line(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(children: [
        Text(label),
        const Spacer(),
        Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null),
      ]),
    );

class ReservationDetailScreen extends ConsumerWidget {
  const ReservationDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiProvider);
    void reload() {
      ref.invalidate(reservationProvider(id));
      ref.invalidate(myReservationsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('रिज़र्वेशन'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(reservationProvider(id).future),
        child: AsyncView(
          value: ref.watch(reservationProvider(id)),
          onRetry: reload,
          data: (r) => ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
            ListTile(
              title: Text(r.number, style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text(dateTime(r.createdAt)),
              trailing: StatusChip(r.status),
            ),
            if (r.isOpen && r.pickupCode != null)
              PickupCodeCard(
                code: r.pickupCode!,
                hint: r.status == 'pending'
                    ? tr('दुकान के कन्फर्म करने का इंतज़ार है। दुकान पर यह कोड बताएं।')
                    : r.pickupAt != null
                        ? tr('पिकअप का समय: {0}। दुकान पर यह कोड बताएं', [timeOnly(r.pickupAt!)])
                        : tr('{0} तक दुकान पहुंचें और यह कोड बताएं', [timeOnly(r.expiresAt)]),
              ),
            if (r.closedReason.isNotEmpty && !r.isOpen)
              Padding(padding: const EdgeInsets.all(16), child: Text(r.closedReason)),
            _line('${r.productName} (${qty(r.quantity)} ${unitLabel(r.unit)})', rupees(r.total), bold: true),
            _line(tr('आपकी बचत'), rupees(r.savings)),
            _line(tr('पेमेंट'), tr('दुकान पर')),
            Card(
              child: ListTile(
                leading: const Icon(Icons.store),
                title: Text(r.shopName),
                subtitle: Text(r.shopAddress),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/shop/${r.shopId}'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: ContactActions(phone: r.shopPhone, latitude: r.shopLatitude, longitude: r.shopLongitude, message: r.number),
            ),
            if (r.isOpen)
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: () async {
                    if (!await confirm(context, tr('रिज़र्वेशन रद्द करें?'))) return;
                    if (context.mounted &&
                        await runAction(context, () => api.post('/reservations/${r.id}/cancel/', {}), success: tr('रद्द किया गया'))) {
                      reload();
                    }
                  },
                  child: Text(tr('रिज़र्वेशन रद्द करें')),
                ),
              ),
            if (r.status == 'completed')
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => showReviewSheet(context, ref, reservationId: r.id, shopName: r.shopName),
                  icon: const Icon(Icons.star_outline),
                  label: Text(tr('दुकान को रेटिंग दें')),
                ),
              ),
            TextButton.icon(
              onPressed: () => context.push('/support/new', extra: {'reservation': r.id, 'category': 'reservation'}),
              icon: const Icon(Icons.help_outline),
              label: Text(tr('मदद चाहिए?')),
            ),
          ]),
        ),
      ),
    );
  }
}

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiProvider);
    void reload() {
      ref.invalidate(orderProvider(id));
      ref.invalidate(myOrdersProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('ऑर्डर'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(orderProvider(id).future),
        child: AsyncView(
          value: ref.watch(orderProvider(id)),
          onRetry: reload,
          data: (o) => ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
            ListTile(
              title: Text(o.number, style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text('${dateTime(o.createdAt)} · ${o.isDelivery ? tr('होम डिलीवरी') : tr('दुकान से पिकअप')}'),
              trailing: StatusChip(o.status),
            ),
            if (o.status == 'pending_payment')
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () async {
                    final ok = await runAction(context, () async {
                      if (!await payOnline(context, api, purpose: 'order', id: o.id)) throw ApiException(tr('पेमेंट पूरा नहीं हुआ'));
                    }, success: tr('पेमेंट हो गया ✅'));
                    if (ok) reload();
                  },
                  child: Text(tr('अभी पेमेंट करें {0}', [rupees(o.total)])),
                ),
              ),
            if (['confirmed', 'ready', 'out_for_delivery'].contains(o.status) && o.pickupCode != null)
              PickupCodeCard(
                code: o.pickupCode!,
                hint: o.isDelivery ? tr('डिलीवरी लेते समय यह कोड बताएं') : tr('दुकान पर यह कोड बताकर सामान लें'),
              ),
            if (o.cancelReason.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(o.cancelReason)),
            for (final item in o.items)
              _line('${item.productName} (${qty(item.quantity)} ${unitLabel(item.unit)})', rupees(item.lineTotal)),
            const Divider(),
            _line(tr('सामान'), rupees(o.subtotal)),
            if (o.couponDiscount > 0) _line(tr('कूपन छूट'), '- ${rupees(o.couponDiscount)}'),
            if (o.deliveryFee > 0) _line(tr('डिलीवरी'), rupees(o.deliveryFee)),
            _line(tr('कुल'), rupees(o.total), bold: true),
            _line(tr('पेमेंट'), '${o.paymentMethod == 'online' ? tr('ऑनलाइन') : tr('कैश')} · ${statusLabel(o.paymentStatus)}'),
            if (o.refunded > 0) _line(tr('रिफंड'), rupees(o.refunded)),
            _line(tr('आपकी बचत'), rupees(o.savings + o.couponDiscount)),
            if (o.isDelivery) Padding(padding: const EdgeInsets.all(16), child: Text(tr('पता: {0}', [o.deliveryAddress]))),
            Card(
              child: ListTile(
                leading: const Icon(Icons.store),
                title: Text(o.shopName),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/shop/${o.shopId}'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: ContactActions(phone: o.shopPhone, latitude: o.shopLatitude, longitude: o.shopLongitude, message: o.number),
            ),
            if (o.status == 'pending_payment' || o.status == 'pending')
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: () async {
                    if (!await confirm(context, tr('ऑर्डर रद्द करें?'), message: o.paymentStatus == 'paid' ? tr('पूरा पैसा वापस आ जाएगा।') : null)) return;
                    if (context.mounted &&
                        await runAction(context, () => api.post('/orders/${o.id}/cancel/', {}), success: tr('ऑर्डर रद्द किया गया'))) {
                      reload();
                    }
                  },
                  child: Text(tr('ऑर्डर रद्द करें')),
                ),
              ),
            if (o.status == 'completed')
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => showReviewSheet(context, ref, orderId: o.id, shopName: o.shopName),
                  icon: const Icon(Icons.star_outline),
                  label: Text(tr('दुकान को रेटिंग दें')),
                ),
              ),
            TextButton.icon(
              onPressed: () => context.push('/support/new', extra: {'order': o.id, 'category': 'order'}),
              icon: const Icon(Icons.help_outline),
              label: Text(tr('ऑर्डर में समस्या? मदद लें')),
            ),
          ]),
        ),
      ),
    );
  }
}
