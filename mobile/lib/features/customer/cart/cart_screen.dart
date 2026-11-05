import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/payments/checkout.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../../core/theme/app_theme.dart';
import '../customer_providers.dart';
import '../offers/offers.dart';
import '../plus/plus_screens.dart';
import '../wallet/wallet_screen.dart';
import 'cart.dart';
import '../../../core/i18n/i18n.dart';

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
  bool _useWallet = false;

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
    }, success: tr('कूपन लग गया'));
  }

  Future<void> _placeOrder(List<CartLine> lines) async {
    if (_fulfilment == 'delivery' && _addressId == null) {
      showMessage(context, tr('डिलीवरी का पता चुनें'));
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
        'use_wallet': _useWallet,
      }));
    });
    if (!placed || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    ref.read(cartProvider.notifier).clear();
    ref.invalidate(walletProvider);
    if (order!['status'] == 'pending_payment') {
      final paid = await runAction(context, () async {
        if (!await payOnline(context, api, purpose: 'order', id: order!['id'])) {
          throw ApiException(tr('पेमेंट पूरा नहीं हुआ। ऑर्डर में जाकर 15 मिनट के अंदर दोबारा पेमेंट करें।'));
        }
      });
      if (paid && mounted) showMessage(context, tr('पेमेंट हो गया ✅'));
    }
    ref.invalidate(myOrdersProvider);
    if (mounted) context.pushReplacement('/success', extra: {'route': '/order/${order!['id']}', 'order': true});
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider);
    if (lines.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('कार्ट'))),
        body: EmptyView(icon: Icons.shopping_cart_outlined, message: tr('कार्ट खाली है')),
      );
    }
    final shop = lines.first.deal.shop;
    final canDeliver = shop.offersDelivery && lines.every((l) => l.deal.canDeliver);
    final canPickup = lines.every((l) => l.deal.canPickup);
    if (!canPickup && _fulfilment == 'pickup') _fulfilment = 'delivery';
    final subtotal = lines.fold<double>(0, (s, l) => s + l.total);
    final savings = lines.fold<double>(0, (s, l) => s + l.savings);
    final isPlus = ref.watch(plusProvider).value?['active'] == true;
    final fee = _fulfilment == 'delivery' && subtotal < _freeDeliveryAbove && !isPlus ? _deliveryFee : 0.0;
    final beforeWallet = subtotal - _discount + fee;
    final balance = walletBalance(ref);
    // Same limit as the server: at most WALLET_MAX_PERCENT_OF_ORDER (50%) of the items.
    final walletUse = _useWallet ? [balance, subtotal * 0.5, beforeWallet].reduce((a, b) => a < b ? a : b) : 0.0;
    final total = beforeWallet - walletUse;

    return Scaffold(
      appBar: AppBar(title: Text(tr('कार्ट · {0}', [shop.name]))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        for (var i = 0; i < lines.length; i++)
          FadeSlideIn(
            index: i,
            child: Dismissible(
              key: ValueKey(lines[i].deal.id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => ref.read(cartProvider.notifier).remove(lines[i].deal.id),
              background: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.only(right: 24),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: AppTheme.radius),
                child: const Icon(Icons.delete_rounded, color: Colors.white, size: 28),
              ),
              child: _CartLineTile(line: lines[i]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Text(tr('हटाने के लिए बाएं स्वाइप करें'), style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        ),
        const Divider(),
        if (_fulfilment == 'delivery' && !isPlus) _FreeDeliveryBar(subtotal: subtotal, target: _freeDeliveryAbove),
        if (isPlus)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(tr('💎 Plus: फ्री डिलीवरी और {0}% और छूट मिलेगी', [5]),
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8A6D1E))),
          ),
        SectionTitle(tr('कैसे लेंगे?')),
        RadioGroup<String>(
          groupValue: _fulfilment,
          onChanged: (v) => setState(() => _fulfilment = v!),
          child: Column(children: [
            RadioListTile(value: 'pickup', enabled: canPickup, title: Text(tr('दुकान से पिकअप'))),
            RadioListTile(
              value: 'delivery',
              enabled: canDeliver,
              title: Text(tr('होम डिलीवरी')),
              subtitle: Text(canDeliver ? tr('{0} से ऊपर फ्री, वरना {1}', [rupees(_freeDeliveryAbove), rupees(_deliveryFee)]) : tr('यह दुकान डिलीवरी नहीं करती')),
            ),
          ]),
        ),
        if (_fulfilment == 'delivery') _AddressPicker(selected: _addressId, onSelect: (id) => setState(() => _addressId = id)),
        SectionTitle(tr('पेमेंट')),
        RadioGroup<String>(
          groupValue: _payment,
          onChanged: (v) => setState(() => _payment = v!),
          child: Column(children: [
            RadioListTile(value: 'online', title: Text(tr('UPI / कार्ड / नेट बैंकिंग'))),
            RadioListTile(value: 'cash', title: Text(_fulfilment == 'delivery' ? tr('कैश ऑन डिलीवरी') : tr('दुकान पर कैश'))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _coupon,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr('कूपन कोड'), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => _applyCoupon(subtotal, shop.id), child: Text(tr('लगाएं'))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            onPressed: () async {
              final code = await pickOffer(context, shop.id);
              if (code == null || !mounted) return;
              _coupon.text = code;
              await _applyCoupon(subtotal, shop.id);
            },
            icon: const Icon(Icons.local_offer_rounded),
            label: Text(tr('ऑफ़र देखें')),
          ),
        ),
        if (balance > 0)
          SwitchListTile(
            secondary: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF15803D)),
            title: Text(tr('वॉलेट इस्तेमाल करें')),
            subtitle: Text(tr('बैलेंस {0}', [rupees(balance)])),
            value: _useWallet,
            onChanged: (v) => setState(() => _useWallet = v),
          ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow(0.05)),
          child: Column(children: [
            _row(tr('सामान'), rupees(subtotal)),
            if (_discount > 0) _row(tr('कूपन छूट'), '- ${rupees(_discount)}', good: true),
            if (fee > 0) _row(tr('डिलीवरी'), rupees(fee)),
            if (walletUse > 0) _row(tr('वॉलेट से'), '- ${rupees(walletUse)}', good: true),
            const Divider(height: 18, indent: 16, endIndent: 16),
            _row(tr('कुल'), rupees(total), bold: true),
          ]),
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.minimal ? AppTheme.accent.withValues(alpha: 0.18) : Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(tr('आप {0} बचा रहे हैं 🎉', [rupees(savings + _discount)]),
                style: TextStyle(color: AppTheme.minimal ? const Color(0xFF0A7A34) : Colors.green.shade800, fontWeight: FontWeight.w800)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _placeOrder(lines),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: Text(_payment == 'online' ? tr('पेमेंट करें {0}', [rupees(total)]) : tr('ऑर्डर करें')),
          ),
        ),
      ]),
    );
  }

  Widget _row(String label, String value, {bool bold = false, bool good = false}) {
    final style = bold
        ? TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.4, color: AppTheme.ink)
        : TextStyle(fontSize: 15, color: good ? const Color(0xFF15803D) : AppTheme.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Text(label, style: bold ? style : TextStyle(fontSize: 15, color: AppTheme.muted)),
        const Spacer(),
        Text(value, style: style),
      ]),
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
                RadioListTile(
                  value: a.id,
                  title: Text(a.label),
                  subtitle: Text([
                    if (a.contactName.isNotEmpty) '👤 ${a.contactName} (${a.contactPhone})',
                    '${a.line}, ${a.city} ${a.pincode}',
                  ].join('\n')),
                ),
            ]),
          ),
          TextButton.icon(
            onPressed: () async {
              await context.push('/addresses/new');
              ref.invalidate(addressesProvider);
            },
            icon: const Icon(Icons.add_location_alt),
            label: Text(tr('नया पता जोड़ें (किसी और के लिए भी)')),
          ),
        ]);
      },
    );
  }
}


/// One cart line: product art, name, unit price and a +/- stepper.
class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deal = line.deal;
    final step = (deal.unit == 'kg' || deal.unit == 'litre') ? 0.5 : 1.0;
    final cart = ref.read(cartProvider.notifier);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: AppTheme.radius, boxShadow: AppTheme.softShadow(0.05)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DealImage(deal.image, size: 64, name: deal.productName, category: deal.categoryName),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(deal.productName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
            Text('${rupees(deal.offerPrice)}/${unitLabel(deal.unit)}', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(rupees(line.total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.ink)),
          ]),
        ),
        Container(
          decoration: BoxDecoration(color: AppTheme.chip, borderRadius: BorderRadius.circular(30)),
          child: Row(children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_rounded),
              onPressed: () => line.quantity - step <= 0 ? cart.remove(deal.id) : cart.add(deal, line.quantity - step),
            ),
            Text(qty(line.quantity), style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded),
              onPressed: line.quantity + step <= deal.quantityAvailable ? () => cart.add(deal, line.quantity + step) : null,
            ),
          ]),
        ),
      ]),
    );
  }
}


/// Blinkit-style "add ₹X more for free delivery" progress bar.
class _FreeDeliveryBar extends StatelessWidget {
  const _FreeDeliveryBar({required this.subtotal, required this.target});

  final double subtotal;
  final double target;

  @override
  Widget build(BuildContext context) {
    final done = subtotal >= target;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: AppTheme.radius),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(done ? tr('🎉 डिलीवरी फ्री हो गई!') : tr('🚚 ₹{0} और जोड़ें, डिलीवरी फ्री', [(target - subtotal).ceil()]),
            style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (subtotal / target).clamp(0, 1)),
          duration: const Duration(milliseconds: 500),
          builder: (_, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: done ? const Color(0xFF16A34A) : AppTheme.accent,
            backgroundColor: AppTheme.chip,
          ),
        ),
      ]),
    );
  }
}
