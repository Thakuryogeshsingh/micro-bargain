import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../merchant_providers.dart';
import '../../../core/i18n/i18n.dart';

class MerchantDealsScreen extends ConsumerWidget {
  const MerchantDealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(merchantDealsProvider);
    List<Deal> only(List<Deal> all, Set<String> statuses) => all.where((d) => statuses.contains(d.status)).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('मेरी डील')),
          bottom: TabBar(tabs: [Tab(text: tr('लाइव')), Tab(text: tr('ड्राफ्ट / रुकी')), Tab(text: tr('पुरानी'))]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await context.push('/merchant/deal-form');
            ref.invalidate(merchantDealsProvider);
          },
          icon: const Icon(Icons.add),
          label: Text(tr('नई डील')),
        ),
        body: AsyncView(
          value: deals,
          onRetry: () => ref.invalidate(merchantDealsProvider),
          data: (all) => TabBarView(children: [
            _DealList(deals: only(all, {'active', 'sold_out'})),
            _DealList(deals: only(all, {'draft', 'paused'})),
            _DealList(deals: only(all, {'expired', 'ended'})),
          ]),
        ),
      ),
    );
  }
}

class _DealList extends ConsumerWidget {
  const _DealList({required this.deals});

  final List<Deal> deals;

  Future<void> _act(BuildContext context, WidgetRef ref, Deal deal, String action) async {
    final api = ref.read(apiProvider);
    if (action == 'update-stock') {
      final value = await askText(context, tr('कुल स्टॉक ({0})', [unitLabel(deal.unit)]), keyboard: const TextInputType.numberWithOptions(decimal: true));
      if (value == null || value.isEmpty || !context.mounted) return;
      if (await runAction(context, () => api.post('/deals/${deal.id}/update-stock/', {'quantity_total': value}), success: tr('स्टॉक अपडेट'))) {
        ref.invalidate(merchantDealsProvider);
      }
      return;
    }
    if (action == 'end' && !await confirm(context, tr('डील बंद करें?'), message: tr('बंद डील दोबारा चालू नहीं होगी।'))) return;
    if (!context.mounted) return;
    final done = {'publish': tr('डील लाइव हो गई 🎉'), 'pause': tr('डील रोकी गई'), 'sold-out': tr('बिक गई मार्क किया'), 'end': tr('डील बंद'), 'duplicate': tr('कॉपी ड्राफ्ट में बनी')};
    if (await runAction(context, () => api.post('/deals/${deal.id}/$action/', {}), success: done[action])) {
      ref.invalidate(merchantDealsProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (deals.isEmpty) return EmptyView(icon: Icons.local_offer_outlined, message: tr('यहां कोई डील नहीं'));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(merchantDealsProvider.future),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: deals.length,
        itemBuilder: (context, i) {
          final d = deals[i];
          final actions = <String, String>{
            if (d.status == 'draft' || d.status == 'paused') 'publish': tr('लाइव करें'),
            if (d.status == 'active') 'pause': tr('रोकें'),
            if (d.status == 'active' || d.status == 'paused') 'sold-out': tr('बिक गई'),
            if (!{'expired', 'ended'}.contains(d.status)) 'update-stock': tr('स्टॉक बदलें'),
            if (!{'expired', 'ended'}.contains(d.status)) 'end': tr('बंद करें'),
            'duplicate': tr('दोबारा लगाएं (कॉपी)'),
          };
          return Card(
            child: ListTile(
              leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: DealImage(d.image, size: 52, name: d.productName, category: d.categoryName)),
              title: Text(d.productName),
              subtitle: Text(
                '${rupees(d.offerPrice)} (${rupees(d.normalPrice)}) · ${d.discountPercent.round()}% off\n'
                '${tr('बिका {0} · रिज़र्व {1} · बचा {2} {3}', [qty(d.quantitySold ?? 0), qty(d.quantityReserved ?? 0), qty(d.quantityAvailable), unitLabel(d.unit)])}\n'
                '${d.status == 'active' ? timeLeft(d.expiresAt) : statusLabel(d.status)}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (a) => _act(context, ref, d, a),
                itemBuilder: (_) => [for (final e in actions.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
              ),
            ),
          );
        },
      ),
    );
  }
}

class DealFormScreen extends ConsumerStatefulWidget {
  const DealFormScreen({super.key});

  @override
  ConsumerState<DealFormScreen> createState() => _DealFormScreenState();
}

class _DealFormScreenState extends ConsumerState<DealFormScreen> {
  final _form = GlobalKey<FormState>();
  Product? _product;
  final _normal = TextEditingController();
  final _offer = TextEditingController();
  final _quantity = TextEditingController();
  final _description = TextEditingController();
  int _minutes = 120;
  String _fulfilment = 'pickup';
  bool _publish = true;
  bool _busy = false;

  // i18n:off (translated where used)
  static const _durations = {60: '1 घंटा', 120: '2 घंटे', 240: '4 घंटे', 480: '8 घंटे', 1440: '1 दिन'};
  // i18n:on

  double get _discount {
    final normal = double.tryParse(_normal.text) ?? 0;
    final offer = double.tryParse(_offer.text) ?? 0;
    return normal > 0 && offer > 0 && offer < normal ? (normal - offer) / normal * 100 : 0;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _product == null) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      final shop = await ref.read(myShopProvider.future);
      await ref.read(apiProvider).post('/deals/create/', {
        'shop': shop!['id'],
        'product': _product!.id,
        'normal_price': _normal.text.trim(),
        'offer_price': _offer.text.trim(),
        'quantity_total': _quantity.text.trim(),
        'duration_minutes': _minutes,
        'fulfilment': _fulfilment,
        'description': _description.text.trim(),
        'publish': _publish,
      });
    }, success: _publish ? tr('डील लाइव हो गई! पास के ग्राहकों को सूचना भेजी जा रही है।') : tr('ड्राफ्ट सेव हुआ'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(merchantDealsProvider);
      ref.invalidate(dashboardProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(merchantProductsProvider);
    final shop = ref.watch(myShopProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(tr('नई डील'))),
      body: AsyncView(
        value: products,
        onRetry: () => ref.invalidate(merchantProductsProvider),
        data: (list) {
          final active = list.where((p) => p.isActive).toList();
          if (active.isEmpty) {
            return EmptyView(
              icon: Icons.inventory_2_outlined,
              message: tr('डील बनाने से पहले प्रोडक्ट जोड़ें'),
              action: FilledButton(
                onPressed: () async {
                  await context.push('/merchant/product-form');
                  ref.invalidate(merchantProductsProvider);
                },
                child: Text(tr('प्रोडक्ट जोड़ें')),
              ),
            );
          }
          return Form(
            key: _form,
            onChanged: () => setState(() {}),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              DropdownButtonFormField<Product>(
                initialValue: _product,
                decoration: InputDecoration(labelText: tr('प्रोडक्ट')),
                items: [for (final p in active) DropdownMenuItem(value: p, child: Text('${p.name} (${unitLabel(p.unit)})'))],
                onChanged: (p) => setState(() {
                  _product = p;
                  _normal.text = qty(p!.standardPrice);
                }),
                validator: (p) => p == null ? tr('चुनें') : null,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _normal,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('सामान्य दाम'), prefixText: '₹ '),
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : tr('दाम डालें'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _offer,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('ऑफर दाम'), prefixText: '₹ '),
                    validator: (v) {
                      final offer = double.tryParse(v ?? '') ?? 0;
                      final normal = double.tryParse(_normal.text) ?? 0;
                      return offer > 0 && offer < normal ? null : tr('सामान्य दाम से कम');
                    },
                  ),
                ),
              ]),
              if (_discount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr('ग्राहक को {0}% छूट दिखेगी', [_discount.round()]), style: TextStyle(color: Colors.green.shade700)),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('कितना बेचना है'), suffixText: _product == null ? '' : unitLabel(_product!.unit)),
                validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : tr('मात्रा डालें'),
              ),
              SectionTitle(tr('डील कब तक चलेगी?')),
              Wrap(spacing: 6, children: [
                for (final e in _durations.entries)
                  ChoiceChip(label: Text(tr(e.value)), selected: _minutes == e.key, onSelected: (_) => setState(() => _minutes = e.key)),
              ]),
              SectionTitle(tr('ग्राहक कैसे लेगा?')),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'pickup', label: Text(tr('पिकअप'))),
                  if (shop?['offers_delivery'] == true) ButtonSegment(value: 'delivery', label: Text(tr('डिलीवरी'))),
                  if (shop?['offers_delivery'] == true) ButtonSegment(value: 'both', label: Text(tr('दोनों'))),
                ],
                selected: {_fulfilment},
                onSelectionChanged: (s) => setState(() => _fulfilment = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _description, maxLines: 2, decoration: InputDecoration(labelText: tr('विवरण (जैसे: आज की ताज़ा खेप)'))),
              SwitchListTile(
                title: Text(tr('अभी लाइव करें')),
                subtitle: Text(tr('पास के ग्राहकों को तुरंत सूचना जाएगी')),
                value: _publish,
                onChanged: (v) => setState(() => _publish = v),
              ),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_publish ? tr('डील लाइव करें') : tr('ड्राफ्ट सेव करें'))),
            ]),
          );
        },
      ),
    );
  }
}
