import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/payments/checkout.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../customer_providers.dart';
import 'cart.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  String _fulfilment = 'pickup';
  String _payment = 'online';
  int? _addressId;
  final _coupon = TextEditingController();
  double _discount = 0;
  bool _busy = false;

  // Must match the server's DELIVERY_FEE / FREE_DELIVERY_ABOVE; the server's total is what is charged.
  static const _deliveryFee = 20.0;
  static const _freeDeliveryAbove = 300.0;

  Future<void> _applyCoupon(double subtotal, int shopId) async {
    await runAction(context, () async {
      final data = await ref.read(apiProvider).post('/orders/check-coupon/', {
        'code': _coupon.text.trim(),
        'shop': shopId,
        'subtotal': subtotal.toStringAsFixed(2),
      });
      setState(() => _discount = double.parse(data['discount'].toString()));
    }, success: 'कूपन लग गया');
  }

  Future<void> _placeOrder(List<CartLine> lines) async {
    if (_fulfilment == 'delivery' && _addressId == null) {
      showMessage(context, 'डिलीवरी का पता चुनें');
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    Map<String, dynamic>? order;
    final placed = await runAction(context, () async {
      order = Map<String, dynamic>.from(await api.post('/orders/create/', {
        'items': [for (final l in lines) {'deal': l.deal.id, 'quantity': l.quantity.toStringAsFixed(2)}],
        'fulfilment': _fulfilment,
        'payment_method': _payment,
        if (_fulfilment == 'delivery') 'address': _addressId,
        if (_coupon.text.trim().isNotEmpty) 'coupon_code': _coupon.text.trim(),
      }));
    });
    if (!placed || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    ref.read(cartProvider.notifier).clear();
    if (order!['status'] == 'pending_payment') {
      final paid = await runAction(context, () async {
        if (!await payOnline(context, api, purpose: 'order', id: order!['id'])) {
          throw ApiException('पेमेंट पूरा नहीं हुआ। ऑर्डर में जाकर 15 मिनट के अंदर दोबारा पेमेंट करें।');
        }
      });
      if (paid && mounted) showMessage(context, 'पेमेंट हो गया ✅');
    }
    ref.invalidate(myOrdersProvider);
    if (mounted) context.pushReplacement('/order/${order!['id']}');
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider);
    final theme = Theme.of(context);
    if (lines.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('कार्ट')),
        body: const EmptyView(icon: Icons.shopping_cart_outlined, message: 'कार्ट खाली है'),
      );
    }
    final shop = lines.first.deal.shop;
    final canDeliver = shop.offersDelivery && lines.every((l) => l.deal.canDeliver);
    final canPickup = lines.every((l) => l.deal.canPickup);
    if (!canPickup && _fulfilment == 'pickup') _fulfilment = 'delivery';
    final subtotal = lines.fold<double>(0, (s, l) => s + l.total);
    final savings = lines.fold<double>(0, (s, l) => s + l.savings);
    final fee = _fulfilment == 'delivery' && subtotal < _freeDeliveryAbove ? _deliveryFee : 0.0;
    final total = subtotal - _discount + fee;

    return Scaffold(
      appBar: AppBar(title: Text('कार्ट · ${shop.name}')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        for (final l in lines)
          ListTile(
            title: Text(l.deal.productName),
            subtitle: Text('${qty(l.quantity)} ${unitLabel(l.deal.unit)} × ${rupees(l.deal.offerPrice)}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(rupees(l.total), style: theme.textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => ref.read(cartProvider.notifier).remove(l.deal.id),
              ),
            ]),
          ),
        const Divider(),
        const SectionTitle('कैसे लेंगे?'),
        RadioGroup<String>(
          groupValue: _fulfilment,
          onChanged: (v) => setState(() => _fulfilment = v!),
          child: Column(children: [
            RadioListTile(value: 'pickup', enabled: canPickup, title: const Text('दुकान से पिकअप')),
            RadioListTile(
              value: 'delivery',
              enabled: canDeliver,
              title: const Text('होम डिलीवरी'),
              subtitle: Text(canDeliver ? '${rupees(_freeDeliveryAbove)} से ऊपर फ्री, वरना ${rupees(_deliveryFee)}' : 'यह दुकान डिलीवरी नहीं करती'),
            ),
          ]),
        ),
        if (_fulfilment == 'delivery') _AddressPicker(selected: _addressId, onSelect: (id) => setState(() => _addressId = id)),
        const SectionTitle('पेमेंट'),
        RadioGroup<String>(
          groupValue: _payment,
          onChanged: (v) => setState(() => _payment = v!),
          child: Column(children: [
            const RadioListTile(value: 'online', title: Text('UPI / कार्ड / नेट बैंकिंग')),
            RadioListTile(value: 'cash', title: Text(_fulfilment == 'delivery' ? 'कैश ऑन डिलीवरी' : 'दुकान पर कैश')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _coupon,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'कूपन कोड', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => _applyCoupon(subtotal, shop.id), child: const Text('लगाएं')),
          ]),
        ),
        const SizedBox(height: 12),
        _row('सामान', rupees(subtotal)),
        if (_discount > 0) _row('कूपन छूट', '- ${rupees(_discount)}'),
        if (fee > 0) _row('डिलीवरी', rupees(fee)),
        _row('कुल', rupees(total), bold: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('आप ${rupees(savings + _discount)} बचा रहे हैं 🎉', style: TextStyle(color: Colors.green.shade700)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy ? null : () => _placeOrder(lines),
            child: Text(_payment == 'online' ? 'पेमेंट करें ${rupees(total)}' : 'ऑर्डर करें'),
          ),
        ),
      ]),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(value, style: style)]),
    );
  }
}

class _AddressPicker extends ConsumerWidget {
  const _AddressPicker({required this.selected, required this.onSelect});

  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressesProvider);
    return AsyncView(
      value: addresses,
      data: (list) {
        if (selected == null && list.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onSelect((list.firstWhere((a) => a.isDefault, orElse: () => list.first)).id));
        }
        return Column(children: [
          RadioGroup<int>(
            groupValue: selected,
            onChanged: (v) => onSelect(v!),
            child: Column(children: [
              for (final a in list)
                RadioListTile(value: a.id, title: Text(a.label), subtitle: Text('${a.line}, ${a.city} ${a.pincode}')),
            ]),
          ),
          TextButton.icon(
            onPressed: () async {
              await context.push('/addresses/new');
              ref.invalidate(addressesProvider);
            },
            icon: const Icon(Icons.add_location_alt),
            label: const Text('नया पता जोड़ें'),
          ),
        ]);
      },
    );
  }
}
