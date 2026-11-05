import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/network/api_client.dart';
import '../../../core/payments/checkout.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../customer/profile/profile_screens.dart';
import '../../settings/language_screen.dart';
import '../merchant_providers.dart';
import '../../../core/i18n/i18n.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    final plan = ref.watch(currentPlanProvider).value;
    Widget item(IconData icon, String title, String route, {String? subtitle}) =>
        ListTile(leading: Icon(icon), title: Text(title), subtitle: subtitle == null ? null : Text(subtitle), onTap: () => context.push(route));

    return Scaffold(
      appBar: AppBar(title: Text(tr('और'))),
      body: ListView(children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.storefront)),
          title: Text(user?.displayName ?? ''),
          subtitle: Text('+91 ${user?.phone ?? ''} · ${plan == null ? '' : tr('{0} प्लान', [plan['plan']['name']])}'),
          trailing: const Icon(Icons.edit),
          onTap: () => editName(context, ref),
        ),
        item(Icons.store, tr('दुकान की जानकारी'), '/merchant/shop-form'),
        item(Icons.inventory_2_outlined, tr('प्रोडक्ट'), '/merchant/products'),
        item(Icons.warehouse_outlined, tr('स्टॉक (इन्वेंटरी)'), '/merchant/inventory'),
        item(Icons.bar_chart, tr('बिक्री और कमीशन'), '/merchant/earnings'),
        item(Icons.star_outline, tr('ग्राहकों के रिव्यू'), '/merchant/reviews'),
        item(Icons.campaign_outlined, tr('प्रमोशन (डील ऊपर दिखाएं)'), '/merchant/promotions'),
        item(Icons.workspace_premium_outlined, tr('प्लान'), '/merchant/plans', subtitle: tr('ज़्यादा डील, बिक्री रिपोर्ट, फीचर्ड लिस्टिंग')),
        const LanguageTile(),
        item(Icons.support_agent, tr('मदद और शिकायत'), '/support'),
        ListTile(leading: const Icon(Icons.logout), title: Text(tr('लॉग आउट')), onTap: () => logout(context, ref)),
        ...legalTiles(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
          title: Text(tr('अकाउंट डिलीट करें'), style: const TextStyle(color: Colors.red)),
          onTap: () => deleteAccount(context, ref),
        ),
      ]),
    );
  }
}

// ---------- inventory ----------

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  Future<void> _adjust(BuildContext context, WidgetRef ref, {int? productId}) async {
    final products = await ref.read(merchantProductsProvider.future);
    if (!context.mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AdjustDialog(products: products, productId: productId),
    );
    if (result == null || !context.mounted) return;
    if (await runAction(context, () => ref.read(apiProvider).post('/inventory/adjust/', result), success: tr('स्टॉक अपडेट हुआ'))) {
      ref.invalidate(inventoryProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('स्टॉक'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _adjust(context, ref),
        icon: const Icon(Icons.add),
        label: Text(tr('स्टॉक जोड़ें / घटाएं')),
      ),
      body: AsyncView(
        value: ref.watch(inventoryProvider),
        onRetry: () => ref.invalidate(inventoryProvider),
        data: (items) => items.isEmpty
            ? EmptyView(
                icon: Icons.warehouse_outlined,
                message: tr('स्टॉक लिखना ज़रूरी नहीं, पर फायदेमंद है: डील उतनी ही बनेगी जितना माल है, और बिक्री अपने आप घटेगी।'),
              )
            : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final i in items)
                  ListTile(
                    leading: Icon(i['is_low'] == true ? Icons.warning_amber : Icons.check_circle_outline,
                        color: i['is_low'] == true ? Colors.orange : Colors.green),
                    title: Text(i['product_name']),
                    subtitle: Text(i['is_low'] == true ? tr('स्टॉक कम है') : tr('अपडेट: {0}', [dateTime(parseTime(i['updated_at'])!)])),
                    trailing: Text('${qty(parseNum(i['quantity_on_hand']))} ${unitLabel(i['unit'])}',
                        style: Theme.of(context).textTheme.titleMedium),
                    onTap: () => _adjust(context, ref, productId: i['product']),
                  ),
              ]),
      ),
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.products, this.productId});

  final List<Product> products;
  final int? productId;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  late int? _product = widget.productId;
  String _reason = 'restock';
  final _amount = TextEditingController();
  final _low = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('स्टॉक बदलें')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: _product,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('प्रोडक्ट')),
            items: [for (final p in widget.products) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (v) => setState(() => _product = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: InputDecoration(labelText: tr('क्या हुआ?')),
            items: [
              DropdownMenuItem(value: 'restock', child: Text(tr('नया माल आया (+)'))),
              DropdownMenuItem(value: 'wastage', child: Text(tr('खराब / फेंका (−)'))),
              DropdownMenuItem(value: 'adjustment', child: Text(tr('गिनती सुधार (+/−)'))),
            ],
            onChanged: (v) => setState(() => _reason = v!),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('मात्रा')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _low,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('कम स्टॉक की चेतावनी कब (ज़रूरी नहीं)')),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('रद्द'))),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amount.text.trim()) ?? 0;
            if (_product == null) return;
            final change = _reason == 'wastage' ? -amount.abs() : (_reason == 'restock' ? amount.abs() : amount);
            Navigator.pop(context, {
              'product': _product,
              'change': change.toStringAsFixed(2),
              'reason': _reason,
              if (_low.text.trim().isNotEmpty) 'low_stock_threshold': _low.text.trim(),
            });
          },
          child: Text(tr('सेव')),
        ),
      ],
    );
  }
}

// ---------- plans ----------

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentPlanProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(tr('प्लान'))),
      body: AsyncView(
        value: ref.watch(plansProvider),
        onRetry: () => ref.invalidate(plansProvider),
        data: (plans) => ListView(children: [
          if (current?['subscription'] != null)
            Card(
              color: Colors.green.shade50,
              child: ListTile(
                title: Text(tr('अभी: {0}', [current!['plan']['name']])),
                subtitle: Text(tr('{0} तक', [dateTime(parseTime(current['subscription']['ends_at'])!)])),
              ),
            ),
          for (final p in plans)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(p['name'], style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    Text(parseNum(p['price_monthly']) == 0 ? tr('फ्री') : tr('{0}/महीना', [rupees(parseNum(p['price_monthly']))]),
                        style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 8),
                  Text(tr('• {0} लाइव डील एक साथ', [p['max_active_deals'] ?? tr('असीमित')])),
                  Text('• ${{'basic': tr('बेसिक डील आंकड़े'), 'sales': tr('बिक्री रिपोर्ट'), 'advanced': tr('एडवांस रिपोर्ट')}[p['analytics']]}'),
                  if (p['priority_support'] == true) Text(tr('• प्राथमिकता सपोर्ट')),
                  if (p['featured_listing'] == true) Text(tr('• आपकी सारी डील सर्च में सबसे ऊपर ⭐')),
                  if (parseNum(p['price_monthly']) > 0) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        final api = ref.read(apiProvider);
                        final ok = await runAction(context, () async {
                          final sub = await api.post('/subscriptions/subscribe/', {'plan': p['code'], 'months': 1});
                          if (!context.mounted || !await payOnline(context, api, purpose: 'subscription', id: sub['id'])) {
                            throw ApiException(tr('पेमेंट पूरा नहीं हुआ'));
                          }
                        }, success: tr('{0} प्लान चालू हो गया 🎉', [p['name']]));
                        if (ok) ref.invalidate(currentPlanProvider);
                      },
                      child: Text(current?['plan']['code'] == p['code'] ? tr('एक महीना और बढ़ाएं') : tr('यह प्लान लें')),
                    ),
                  ],
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------- promotions ----------

class PromotionsScreen extends ConsumerWidget {
  const PromotionsScreen({super.key});

  Future<void> _featureDeal(BuildContext context, WidgetRef ref) async {
    final deals = (await ref.read(merchantDealsProvider.future)).where((d) => d.status == 'active').toList();
    if (!context.mounted) return;
    if (deals.isEmpty) {
      showMessage(context, tr('पहले कोई डील लाइव करें'));
      return;
    }
    Deal? deal = deals.first;
    var days = 1;
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('डील फीचर करें')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<Deal>(
              initialValue: deal,
              isExpanded: true,
              items: [for (final d in deals) DropdownMenuItem(value: d, child: Text(d.productName))],
              onChanged: (v) => setState(() => deal = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text(tr('कितने दिन')),
              const Spacer(),
              IconButton(onPressed: days > 1 ? () => setState(() => days--) : null, icon: const Icon(Icons.remove)),
              Text('$days'),
              IconButton(onPressed: days < 30 ? () => setState(() => days++) : null, icon: const Icon(Icons.add)),
            ]),
            Text(tr('कीमत: {0}', [rupees(49 * days)])),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('रद्द'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('पेमेंट करें'))),
          ],
        ),
      ),
    );
    if (go != true || deal == null || !context.mounted) return;
    final api = ref.read(apiProvider);
    final ok = await runAction(context, () async {
      final ad = await api.post('/advertisements/create/', {'placement': 'featured_deal', 'deal': deal!.id, 'days': days});
      if (!context.mounted || !await payOnline(context, api, purpose: 'advertisement', id: ad['id'])) {
        throw ApiException(tr('पेमेंट पूरा नहीं हुआ'));
      }
    }, success: tr('प्रमोशन चालू! आपकी डील सबसे ऊपर दिखेगी ⭐'));
    if (ok) ref.invalidate(adsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('प्रमोशन'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _featureDeal(context, ref),
        icon: const Icon(Icons.campaign),
        label: Text(tr('डील फीचर करें')),
      ),
      body: AsyncView(
        value: ref.watch(adsProvider),
        onRetry: () => ref.invalidate(adsProvider),
        data: (ads) => ads.isEmpty
            ? EmptyView(icon: Icons.campaign_outlined, message: tr('फीचर्ड डील पास के ग्राहकों को सबसे ऊपर दिखती है। ₹49/दिन से शुरू।'))
            : ListView(children: [
                for (final a in ads)
                  ListTile(
                    leading: Icon(a['placement'] == 'featured_deal' ? Icons.star : Icons.image),
                    title: Text(a['placement'] == 'featured_deal' ? tr('फीचर्ड डील') : (a['title'] ?? tr('बैनर'))),
                    subtitle: Text(tr('{0} दिन · {1} · {2} बार दिखा, {3} क्लिक', [a['days'], rupees(parseNum(a['price'])), a['impressions'], a['clicks']])),
                    trailing: Chip(label: Text({'active': tr('चालू'), 'pending_payment': tr('पेमेंट बाकी'), 'expired': tr('खत्म'), 'rejected': tr('अस्वीकार')}[a['status']] ?? a['status'])),
                  ),
              ]),
      ),
    );
  }
}

// ---------- reviews ----------

class MerchantReviewsScreen extends ConsumerWidget {
  const MerchantReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('ग्राहकों के रिव्यू'))),
      body: AsyncView(
        value: ref.watch(merchantReviewsProvider),
        onRetry: () => ref.invalidate(merchantReviewsProvider),
        data: (reviews) => reviews.isEmpty
            ? EmptyView(icon: Icons.star_outline, message: tr('अभी कोई रिव्यू नहीं'))
            : ListView(children: [
                for (final r in reviews)
                  Card(
                    child: ListTile(
                      leading: Stars(r.rating, size: 14),
                      title: Text(r.comment.isEmpty ? tr('(कोई टिप्पणी नहीं)') : r.comment),
                      subtitle: Text('${r.customerName} · ${dateTime(r.createdAt)}${r.reply.isEmpty ? '' : tr('\nआपका जवाब: {0}', [r.reply])}'),
                      isThreeLine: r.reply.isNotEmpty,
                      trailing: IconButton(
                        icon: const Icon(Icons.reply),
                        onPressed: () async {
                          final text = await askText(context, tr('जवाब लिखें'));
                          if (text == null || text.isEmpty || !context.mounted) return;
                          if (await runAction(context, () => ref.read(apiProvider).post('/reviews/${r.id}/reply/', {'reply': text}))) {
                            ref.invalidate(merchantReviewsProvider);
                          }
                        },
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }
}

// ---------- earnings ----------

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commission = ref.watch(commissionSummaryProvider);
    final sales = ref.watch(salesProvider(30));
    return Scaffold(
      appBar: AppBar(title: Text(tr('बिक्री और कमीशन'))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        SectionTitle(tr('पिछले 30 दिन की बिक्री')),
        sales.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(e is ApiException && e.code == 'upgrade_required' ? tr('बिक्री रिपोर्ट Basic / Premium प्लान में है') : e.toString()),
              trailing: TextButton(onPressed: () => context.push('/merchant/plans'), child: Text(tr('प्लान देखें'))),
            ),
          ),
          data: (s) {
            final daily = (s['daily'] as List).cast<Map<String, dynamic>>();
            final maxSale = daily.fold<double>(1, (m, d) => parseNum(d['sales']) > m ? parseNum(d['sales']) : m);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatTile(label: tr('कुल बिक्री'), value: parseNum(s['total_sales']), format: rupees, icon: Icons.currency_rupee_rounded),
              const SizedBox(height: 12),
              for (final d in daily)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(width: 70, child: Text(d['day'].toString().substring(5), style: Theme.of(context).textTheme.bodySmall)),
                    Expanded(
                      child: LinearProgressIndicator(value: parseNum(d['sales']) / maxSale, minHeight: 10, borderRadius: BorderRadius.circular(4)),
                    ),
                    SizedBox(width: 80, child: Text(rupees(parseNum(d['sales'])), textAlign: TextAlign.end)),
                  ]),
                ),
              SectionTitle(tr('सबसे ज़्यादा बिकने वाले')),
              for (final p in (s['top_products'] as List))
                ListTile(dense: true, title: Text(p['product']), trailing: Text(rupees(parseNum(p['sales'])))),
            ]);
          },
        ),
        SectionTitle(tr('प्लेटफ़ॉर्म कमीशन')),
        AsyncView(
          value: commission,
          data: (c) => Column(children: [
            ListTile(title: Text(tr('बकाया (अभी देना है)')), trailing: Text(rupees(parseNum(c['pending'])))),
            ListTile(title: Text(tr('चुका दिया')), trailing: Text(rupees(parseNum(c['settled'])))),
            ListTile(title: Text(tr('रिफंड के कारण वापस')), trailing: Text(rupees(parseNum(c['reversed'])))),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(tr('हर पूरी हुई बिक्री पर एक छोटा कमीशन (जैसे 3%) लगता है। हिसाब हर हफ्ते होता है।')),
            ),
          ]),
        ),
      ]),
    );
  }
}
