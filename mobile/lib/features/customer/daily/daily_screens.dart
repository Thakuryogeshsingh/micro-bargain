import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';
import '../customer_providers.dart';

/// Weekday initials, Monday first (matches the server's "1111111").
List<String> weekdayLetters() => [tr('सो'), tr('मं'), tr('बु'), tr('गु'), tr('शु'), tr('श'), tr('र')];

final myDailyProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.watch(apiProvider).get('/daily/') as List;
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

final _shopProductsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, int>((ref, shopId) async {
  final rows = await ref.watch(apiProvider).get('/daily/products/', query: {'shop': shopId}) as List;
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

/// "Get it every day" sheet from a shop's page.
Future<void> showSubscribeSheet(BuildContext context, ShopSummary shop) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SubscribeSheet(shop: shop),
  );
}

class _SubscribeSheet extends ConsumerStatefulWidget {
  const _SubscribeSheet({required this.shop});

  final ShopSummary shop;

  @override
  ConsumerState<_SubscribeSheet> createState() => _SubscribeSheetState();
}

class _SubscribeSheetState extends ConsumerState<_SubscribeSheet> {
  Map<String, dynamic>? _product;
  double _qty = 1;
  String _days = '1111111';
  String _slot = 'morning';
  int? _address;

  double get _step => ['kg', 'litre'].contains(_product?['unit']) ? 0.5 : 1;

  Future<void> _save() async {
    if (_product == null) {
      showMessage(context, tr('पहले सामान चुनें'), error: true);
      return;
    }
    final ok = await runAction(context, () => ref.read(apiProvider).post('/daily/', {
          'product': _product!['id'],
          'quantity': _qty.toStringAsFixed(2),
          'weekdays': _days,
          'slot': _slot,
          'address': ?_address,
        }), success: tr('रोज़ाना डिलीवरी शुरू! दुकान को बता दिया गया।'));
    if (ok && mounted) {
      ref.invalidate(myDailyProvider);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(_shopProductsProvider(widget.shop.id));
    final addresses = ref.watch(addressesProvider).value ?? const <Address>[];
    final price = parseNum(_product?['price']);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(tr('रोज़ मंगवाएं'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.6, color: AppTheme.ink)),
          Text(tr('{0} से हर दिन, बिना बार-बार ऑर्डर किए। पैसे महीने के आख़िर में दुकान को।', [widget.shop.name]),
              style: TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 16),
          SizedBox(
            height: 112,
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (list) => ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final selected = _product?['id'] == p['id'];
                  return Pressable(
                    onTap: () => setState(() {
                      _product = p;
                      _qty = 1;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 104,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(width: 2, color: selected ? (AppTheme.minimal ? AppTheme.accent : AppTheme.primary) : AppTheme.chip),
                      ),
                      child: Column(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: p['image'] != null
                              ? CachedNetworkImage(imageUrl: p['image'], height: 52, width: 92, fit: BoxFit.cover)
                              : Container(height: 52, width: 92, color: AppTheme.chip, child: const Icon(Icons.shopping_basket_outlined)),
                        ),
                        const SizedBox(height: 4),
                        Text(p['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        Text('${rupees(parseNum(p['price']))}/${unitLabel(p['unit'])}', style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_product != null) ...[
            const SizedBox(height: 16),
            Row(children: [
              Text(tr('रोज़ कितना?'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton.outlined(onPressed: _qty > _step ? () => setState(() => _qty -= _step) : null, icon: const Icon(Icons.remove)),
              SizedBox(
                width: 80,
                child: Text('${qty(_qty)} ${unitLabel(_product!['unit'])}',
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              IconButton.outlined(onPressed: () => setState(() => _qty += _step), icon: const Icon(Icons.add)),
            ]),
          ],
          const SizedBox(height: 12),
          Text(tr('किन दिनों?'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Pressable(
                    onTap: () => setState(() {
                      final chars = _days.split('');
                      chars[i] = chars[i] == '1' ? '0' : '1';
                      _days = chars.join();
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _days[i] == '1' ? AppTheme.ink : AppTheme.chip,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FittedBox(
                        child: Text(weekdayLetters()[i],
                            style: TextStyle(fontWeight: FontWeight.w800, color: _days[i] == '1' ? AppTheme.background : AppTheme.ink)),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'morning', label: Text(tr('सुबह')), icon: const Icon(Icons.wb_sunny_outlined)),
              ButtonSegment(value: 'evening', label: Text(tr('शाम')), icon: const Icon(Icons.nights_stay_outlined)),
            ],
            selected: {_slot},
            onSelectionChanged: (v) => setState(() => _slot = v.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _address,
            decoration: InputDecoration(labelText: tr('कहाँ पहुंचाएं?')),
            items: [
              DropdownMenuItem(value: null, child: Text(tr('मैं दुकान से ले लूंगा'))),
              for (final a in addresses) DropdownMenuItem(value: a.id, child: Text('${a.label} · ${a.line}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _address = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: Text(_product == null
                ? tr('रोज़ाना शुरू करें')
                : tr('रोज़ाना शुरू करें · {0}/दिन', [rupees(price * _qty)])),
          ),
        ]),
      ),
    );
  }
}

/// Profile -> My daily orders.
class MyDailyScreen extends ConsumerWidget {
  const MyDailyScreen({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, Map d, String status, {String? until}) async {
    final ok = await runAction(context, () => ref.read(apiProvider).post('/daily/${d['id']}/status/', {
          'status': status,
          'paused_until': ?until,
        }));
    if (ok) ref.invalidate(myDailyProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('रोज़ाना डिलीवरी'))),
      body: AsyncView(
        value: ref.watch(myDailyProvider),
        onRetry: () => ref.invalidate(myDailyProvider),
        data: (rows) => rows.isEmpty
            ? EmptyView(
                icon: Icons.event_repeat_rounded,
                message: tr('अभी कोई रोज़ाना डिलीवरी नहीं।\nदूध या ब्रेड वाली दुकान खोलकर "रोज़ मंगवाएं" दबाएं।'),
                action: OutlinedButton(onPressed: () => context.go('/customer'), child: Text(tr('दुकानें देखें'))),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final d = rows[i];
                  final paused = d['status'] == 'paused';
                  final days = d['weekdays'] as String;
                  return FadeSlideIn(
                    index: i,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text('${d['product_name']} · ${qty(parseNum(d['quantity']))} ${unitLabel(d['unit'])}',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ),
                            StatusChip(d['status']),
                          ]),
                          Text('${d['shop_name']} · ${d['slot'] == 'morning' ? tr('सुबह') : tr('शाम')}', style: TextStyle(color: AppTheme.muted)),
                          const SizedBox(height: 10),
                          Row(children: [
                            for (var k = 0; k < 7; k++)
                              Container(
                                margin: const EdgeInsets.only(right: 4),
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: days[k] == '1' ? AppTheme.ink : AppTheme.chip, shape: BoxShape.circle),
                                padding: const EdgeInsets.all(3),
                                child: FittedBox(
                                  child: Text(weekdayLetters()[k],
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: days[k] == '1' ? AppTheme.background : AppTheme.muted)),
                                ),
                              ),
                          ]),
                          const SizedBox(height: 10),
                          Text(tr('इस महीने का बिल: {0}', [rupees(parseNum(d['month_total']))]),
                              style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, children: [
                            if (paused)
                              FilledButton.tonal(onPressed: () => _set(context, ref, d, 'active'), child: Text(tr('फिर शुरू करें')))
                            else
                              OutlinedButton(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 60)),
                                    helpText: tr('कब तक रोकें?'),
                                  );
                                  if (picked != null && context.mounted) {
                                    await _set(context, ref, d, 'paused', until: picked.toIso8601String().substring(0, 10));
                                  }
                                },
                                child: Text(tr('कुछ दिन रोकें')),
                              ),
                            TextButton(
                              onPressed: () async {
                                if (await confirm(context, tr('रोज़ाना डिलीवरी बंद करें?'), icon: Icons.event_busy_rounded, danger: true)) {
                                  if (context.mounted) await _set(context, ref, d, 'cancelled');
                                }
                              },
                              child: Text(tr('बंद करें'), style: const TextStyle(color: Color(0xFFE5484D))),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
