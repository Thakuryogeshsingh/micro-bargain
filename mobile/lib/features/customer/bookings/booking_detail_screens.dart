import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/payments/checkout.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/tracking.dart';
import '../../../shared/models/models.dart';
import '../cart/cart.dart';
import '../customer_providers.dart';
import '../quality/quality_screens.dart';
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
        child: Column(
          children: [
            Text(hint, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              code,
              style: TextStyle(
                fontSize: 44,
                letterSpacing: 14,
                fontWeight: FontWeight.bold,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _line(String label, String value, {bool bold = false}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
  child: Row(
    children: [
      Text(label),
      const Spacer(),
      Text(
        value,
        style: bold
            ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
            : null,
      ),
    ],
  ),
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
      body: AutoRefresh(
        onTick: () => ref.invalidate(reservationProvider(id)),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(reservationProvider(id).future),
          child: AsyncView(
            value: ref.watch(reservationProvider(id)),
            onRetry: reload,
            data: (r) => ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  title: Text(
                    r.number,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  subtitle: Text(dateTime(r.createdAt)),
                  trailing: StatusChip(r.status),
                ),
                TrackingTimeline(
                  failed: [
                    'rejected',
                    'cancelled',
                    'expired',
                  ].contains(r.status),
                  failedText:
                      '${statusLabel(r.status)}${r.closedReason.isEmpty ? '' : ' — ${r.closedReason}'}',
                  steps: [
                    TrackStep(
                      Icons.bookmark_added_rounded,
                      tr('रिज़र्व हुआ'),
                      at: r.createdAt,
                      done: true,
                    ),
                    TrackStep(
                      Icons.storefront_rounded,
                      tr('दुकान ने कन्फर्म किया'),
                      at: r.confirmedAt,
                      done: r.status == 'confirmed' || r.status == 'completed',
                    ),
                    TrackStep(
                      Icons.shopping_bag_rounded,
                      tr('सामान लिया'),
                      at: r.completedAt,
                      done: r.status == 'completed',
                    ),
                  ],
                ),
                if (r.isOpen && r.pickupCode != null)
                  PickupCodeCard(
                    code: r.pickupCode!,
                    hint: r.status == 'pending'
                        ? tr(
                            'दुकान के कन्फर्म करने का इंतज़ार है। दुकान पर यह कोड बताएं।',
                          )
                        : r.pickupAt != null
                        ? tr('पिकअप का समय: {0}। दुकान पर यह कोड बताएं', [
                            timeOnly(r.pickupAt!),
                          ])
                        : tr('{0} तक दुकान पहुंचें और यह कोड बताएं', [
                            timeOnly(r.expiresAt),
                          ]),
                  ),
                if (r.closedReason.isNotEmpty && !r.isOpen)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(r.closedReason),
                  ),
                _line(
                  '${r.productName} (${qty(r.quantity)} ${unitLabel(r.unit)})',
                  rupees(r.total),
                  bold: true,
                ),
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
                  child: ContactActions(
                    phone: r.shopPhone,
                    latitude: r.shopLatitude,
                    longitude: r.shopLongitude,
                    message: r.number,
                  ),
                ),
                if (r.isOpen)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton(
                      onPressed: () async {
                        if (!await confirm(
                          context,
                          tr('रिज़र्वेशन रद्द करें?'),
                        )) {
                          return;
                        }
                        if (context.mounted &&
                            await runAction(
                              context,
                              () =>
                                  api.post('/reservations/${r.id}/cancel/', {}),
                              success: tr('रद्द किया गया'),
                            )) {
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
                      onPressed: () => showReviewSheet(
                        context,
                        ref,
                        reservationId: r.id,
                        shopName: r.shopName,
                      ),
                      icon: const Icon(Icons.star_outline),
                      label: Text(tr('दुकान को रेटिंग दें')),
                    ),
                  ),
                if (canComplain(r.status, r.completedAt)) ComplaintButton(reservationId: r.id, shopName: r.shopName),
                TextButton.icon(
                  onPressed: () => context.push(
                    '/support/new',
                    extra: {'reservation': r.id, 'category': 'reservation'},
                  ),
                  icon: const Icon(Icons.help_outline),
                  label: Text(tr('मदद चाहिए?')),
                ),
              ],
            ),
          ),
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
      body: AutoRefresh(
        onTick: () => ref.invalidate(orderProvider(id)),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(orderProvider(id).future),
          child: AsyncView(
            value: ref.watch(orderProvider(id)),
            onRetry: reload,
            data: (o) => ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  title: Text(
                    o.number,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  subtitle: Text(
                    '${dateTime(o.createdAt)} · ${o.isDelivery ? tr('होम डिलीवरी') : tr('दुकान से पिकअप')}',
                  ),
                  trailing: StatusChip(o.status),
                ),
                TrackingTimeline(
                  failed: ['cancelled', 'refunded'].contains(o.status),
                  failedText:
                      '${statusLabel(o.status)}${o.cancelReason.isEmpty ? '' : ' — ${o.cancelReason}'}',
                  steps: [
                    TrackStep(
                      Icons.receipt_long_rounded,
                      tr('ऑर्डर हुआ'),
                      at: o.createdAt,
                      done: o.status != 'pending_payment',
                    ),
                    TrackStep(
                      Icons.storefront_rounded,
                      tr('दुकान ने स्वीकार किया'),
                      at: o.confirmedAt,
                      done: [
                        'confirmed',
                        'ready',
                        'out_for_delivery',
                        'completed',
                      ].contains(o.status),
                    ),
                    TrackStep(
                      o.isDelivery
                          ? Icons.delivery_dining_rounded
                          : Icons.inventory_2_rounded,
                      o.isDelivery
                          ? tr('डिलीवरी के रास्ते में')
                          : tr('पिकअप के लिए तैयार'),
                      at: o.readyAt,
                      done: [
                        'ready',
                        'out_for_delivery',
                        'completed',
                      ].contains(o.status),
                    ),
                    TrackStep(
                      Icons.celebration_rounded,
                      tr('पूरा हुआ'),
                      at: o.completedAt,
                      done: o.status == 'completed',
                    ),
                  ],
                ),
                if (o.status == 'pending_payment')
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () async {
                        final ok = await runAction(context, () async {
                          if (!await payOnline(
                            context,
                            api,
                            purpose: 'order',
                            id: o.id,
                          )) {
                            throw ApiException(tr('पेमेंट पूरा नहीं हुआ'));
                          }
                        }, success: tr('पेमेंट हो गया ✅'));
                        if (ok) reload();
                      },
                      child: Text(tr('अभी पेमेंट करें {0}', [rupees(o.total)])),
                    ),
                  ),
                if ([
                      'confirmed',
                      'ready',
                      'out_for_delivery',
                    ].contains(o.status) &&
                    o.pickupCode != null)
                  PickupCodeCard(
                    code: o.pickupCode!,
                    hint: o.isDelivery
                        ? tr('डिलीवरी लेते समय यह कोड बताएं')
                        : tr('दुकान पर यह कोड बताकर सामान लें'),
                  ),
                if (o.cancelReason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(o.cancelReason),
                  ),
                for (final item in o.items)
                  _line(
                    '${item.productName} (${qty(item.quantity)} ${unitLabel(item.unit)})',
                    rupees(item.lineTotal),
                  ),
                const Divider(),
                _line(tr('सामान'), rupees(o.subtotal)),
                if (o.couponDiscount > 0)
                  _line(tr('कूपन छूट'), '- ${rupees(o.couponDiscount)}'),
                if (o.plusDiscount > 0)
                  _line('💎 Plus', '- ${rupees(o.plusDiscount)}'),
                if (o.deliveryFee > 0)
                  _line(tr('डिलीवरी'), rupees(o.deliveryFee)),
                _line(tr('कुल'), rupees(o.total), bold: true),
                _line(
                  tr('पेमेंट'),
                  '${o.paymentMethod == 'online' ? tr('ऑनलाइन') : tr('कैश')} · ${statusLabel(o.paymentStatus)}',
                ),
                if (o.refunded > 0) _line(tr('रिफंड'), rupees(o.refunded)),
                _line(tr('आपकी बचत'), rupees(o.savings + o.couponDiscount)),
                if (o.isDelivery)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text([
                      tr('पता: {0}', [o.deliveryAddress]),
                      if (o.recipientName.isNotEmpty) tr('पाने वाले: {0} ({1})', [o.recipientName, o.recipientPhone]),
                    ].join('\n')),
                  ),
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
                  child: ContactActions(
                    phone: o.shopPhone,
                    latitude: o.shopLatitude,
                    longitude: o.shopLongitude,
                    message: o.number,
                  ),
                ),
                if (o.status == 'pending_payment' || o.status == 'pending')
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton(
                      onPressed: () async {
                        if (!await confirm(
                          context,
                          tr('ऑर्डर रद्द करें?'),
                          message: o.paymentStatus == 'paid'
                              ? tr('पूरा पैसा वापस आ जाएगा।')
                              : null,
                        )) {
                          return;
                        }
                        if (context.mounted &&
                            await runAction(
                              context,
                              () => api.post('/orders/${o.id}/cancel/', {}),
                              success: tr('ऑर्डर रद्द किया गया'),
                            )) {
                          reload();
                        }
                      },
                      child: Text(tr('ऑर्डर रद्द करें')),
                    ),
                  ),
                if (o.status == 'completed' || o.status == 'cancelled')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => reorder(context, ref, o),
                      icon: const Icon(Icons.replay_rounded),
                      label: Text(tr('दोबारा ऑर्डर करें')),
                    ),
                  ),
                if (o.status == 'completed')
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: () => showReviewSheet(
                        context,
                        ref,
                        orderId: o.id,
                        shopName: o.shopName,
                      ),
                      icon: const Icon(Icons.star_outline),
                      label: Text(tr('दुकान को रेटिंग दें')),
                    ),
                  ),
                if (canComplain(o.status, o.completedAt)) ComplaintButton(orderId: o.id, shopName: o.shopName),
                TextButton.icon(
                  onPressed: () => context.push(
                    '/support/new',
                    extra: {'order': o.id, 'category': 'order'},
                  ),
                  icon: const Icon(Icons.help_outline),
                  label: Text(tr('ऑर्डर में समस्या? मदद लें')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts the items of a past order back in the cart (only deals that are still live, up to what is left).
Future<void> reorder(BuildContext context, WidgetRef ref, Order order) async {
  final api = ref.read(apiProvider);
  final cart = ref.read(cartProvider.notifier);
  cart.clear();
  var added = 0;
  for (final item in order.items) {
    try {
      final deal = Deal.fromJson(await api.get('/deals/${item.dealId}/'));
      if (!deal.isLive) continue;
      cart.add(
        deal,
        item.quantity > deal.quantityAvailable
            ? deal.quantityAvailable
            : item.quantity,
      );
      added++;
    } on ApiException {
      continue;
    }
  }
  if (!context.mounted) return;
  if (added == 0) {
    showMessage(context, tr('इस ऑर्डर की डील अब उपलब्ध नहीं हैं'));
    return;
  }
  context.push('/cart');
}
