import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../cart/cart.dart';
import '../customer_providers.dart';

Future<void> openDirections(double lat, double lng) =>
    launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'), mode: LaunchMode.externalApplication);

class DealDetailScreen extends ConsumerWidget {
  const DealDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('डील')),
      body: AsyncView(
        value: ref.watch(dealProvider(id)),
        onRetry: () => ref.invalidate(dealProvider(id)),
        data: (deal) => _DealBody(deal: deal),
      ),
    );
  }
}

class _DealBody extends ConsumerStatefulWidget {
  const _DealBody({required this.deal});

  final Deal deal;

  @override
  ConsumerState<_DealBody> createState() => _DealBodyState();
}

class _DealBodyState extends ConsumerState<_DealBody> {
  double _qty = 1;
  bool _busy = false;

  Deal get deal => widget.deal;

  // Loose items (kg, litre) can be bought in halves; the rest in whole units.
  double get _step => (deal.unit == 'kg' || deal.unit == 'litre') ? 0.5 : 1;

  Future<void> _reserve() async {
    setState(() => _busy = true);
    Map<String, dynamic>? created;
    await runAction(context, () async {
      created = Map<String, dynamic>.from(
          await ref.read(apiProvider).post('/reservations/create/', {'deal': deal.id, 'quantity': _qty.toStringAsFixed(2)}));
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (created != null) {
      ref.invalidate(myReservationsProvider);
      context.pushReplacement('/reservation/${created!['id']}');
    }
  }

  Future<void> _addToCart() async {
    final cart = ref.read(cartProvider.notifier);
    if (!cart.add(deal, _qty)) {
      final replace = await confirm(context, 'कार्ट में दूसरी दुकान का सामान है',
          message: 'एक ऑर्डर में एक ही दुकान का सामान आ सकता है। पुराना कार्ट हटा कर यह डालें?', ok: 'हाँ, बदलें');
      if (!replace) return;
      cart.replaceWith(deal, _qty);
    }
    if (mounted) showMessage(context, 'कार्ट में जोड़ा गया');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = deal.offerPrice * _qty;
    final saved = (deal.normalPrice - deal.offerPrice) * _qty;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      AspectRatio(aspectRatio: 16 / 10, child: DealImage(deal.image, size: double.infinity)),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(deal.productName, style: theme.textTheme.headlineSmall)),
            StatusChip(deal.status),
          ]),
          const SizedBox(height: 6),
          PriceLine(offer: deal.offerPrice, normal: deal.normalPrice, unit: deal.unit, large: true),
          Text('${deal.discountPercent.round()}% की बचत', style: TextStyle(color: Colors.green.shade700)),
          const SizedBox(height: 8),
          Ticker(
            builder: (_) => Text('⏱ ${timeLeft(deal.expiresAt)} · ${qty(deal.quantityAvailable)} ${unitLabel(deal.unit)} बचा',
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
          ),
          if (deal.description.isNotEmpty) ...[const SizedBox(height: 12), Text(deal.description)],
        ]),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.store),
          title: Text(deal.shop.name),
          subtitle: Text('${deal.shop.address}\n${distance(deal.distanceM)}'),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'रास्ता देखें',
            icon: const Icon(Icons.directions),
            onPressed: () => openDirections(deal.shop.latitude, deal.shop.longitude),
          ),
          onTap: () => context.push('/shop/${deal.shop.id}'),
        ),
      ),
      if (deal.isLive) ...[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text('मात्रा', style: theme.textTheme.titleMedium),
            const Spacer(),
            IconButton.outlined(
              onPressed: _qty > _step ? () => setState(() => _qty -= _step) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 90,
              child: Text('${qty(_qty)} ${unitLabel(deal.unit)}', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            ),
            IconButton.outlined(
              onPressed: _qty + _step <= deal.quantityAvailable ? () => setState(() => _qty += _step) : null,
              icon: const Icon(Icons.add),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('कुल ${rupees(total)} · आपकी बचत ${rupees(saved)}', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        if (deal.canPickup)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FilledButton.icon(
              onPressed: _busy ? null : _reserve,
              icon: const Icon(Icons.bookmark_added),
              label: const Text('रिज़र्व करें · दुकान पर पैसे दें'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _addToCart,
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(deal.canDeliver ? 'कार्ट में डालें (ऑनलाइन पेमेंट / डिलीवरी)' : 'कार्ट में डालें (ऑनलाइन पेमेंट)'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('रिज़र्व करने पर सामान 45 मिनट तक आपके लिए रखा जाएगा। दुकान पर पिकअप कोड बताकर पैसे दें।',
              style: theme.textTheme.bodySmall),
        ),
      ] else
        const Padding(padding: EdgeInsets.all(16), child: Text('यह डील अब उपलब्ध नहीं है।')),
    ]);
  }
}
