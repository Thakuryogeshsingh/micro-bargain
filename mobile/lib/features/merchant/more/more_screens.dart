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
import '../merchant_providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    final plan = ref.watch(currentPlanProvider).value;
    Widget item(IconData icon, String title, String route, {String? subtitle}) =>
        ListTile(leading: Icon(icon), title: Text(title), subtitle: subtitle == null ? null : Text(subtitle), onTap: () => context.push(route));

    return Scaffold(
      appBar: AppBar(title: const Text('और')),
      body: ListView(children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.storefront)),
          title: Text(user?.displayName ?? ''),
          subtitle: Text('+91 ${user?.phone ?? ''} · ${plan == null ? '' : '${plan['plan']['name']} प्लान'}'),
          trailing: const Icon(Icons.edit),
          onTap: () => editName(context, ref),
        ),
        item(Icons.store, 'दुकान की जानकारी', '/merchant/shop-form'),
        item(Icons.inventory_2_outlined, 'प्रोडक्ट', '/merchant/products'),
        item(Icons.warehouse_outlined, 'स्टॉक (इन्वेंटरी)', '/merchant/inventory'),
        item(Icons.bar_chart, 'बिक्री और कमीशन', '/merchant/earnings'),
        item(Icons.star_outline, 'ग्राहकों के रिव्यू', '/merchant/reviews'),
        item(Icons.campaign_outlined, 'प्रमोशन (डील ऊपर दिखाएं)', '/merchant/promotions'),
        item(Icons.workspace_premium_outlined, 'प्लान', '/merchant/plans', subtitle: 'ज़्यादा डील, बिक्री रिपोर्ट, फीचर्ड लिस्टिंग'),
        item(Icons.support_agent, 'मदद और शिकायत', '/support'),
        ListTile(leading: const Icon(Icons.logout), title: const Text('लॉग आउट'), onTap: () => logout(context, ref)),
        ...legalTiles(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
          title: const Text('अकाउंट डिलीट करें', style: TextStyle(color: Colors.red)),
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
    if (await runAction(context, () => ref.read(apiProvider).post('/inventory/adjust/', result), success: 'स्टॉक अपडेट हुआ')) {
      ref.invalidate(inventoryProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('स्टॉक')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _adjust(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('स्टॉक जोड़ें / घटाएं'),
      ),
      body: AsyncView(
        value: ref.watch(inventoryProvider),
        onRetry: () => ref.invalidate(inventoryProvider),
        data: (items) => items.isEmpty
            ? const EmptyView(
                icon: Icons.warehouse_outlined,
                message: 'स्टॉक लिखना ज़रूरी नहीं, पर फायदेमंद है: डील उतनी ही बनेगी जितना माल है, और बिक्री अपने आप घटेगी।',
              )
            : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final i in items)
                  ListTile(
                    leading: Icon(i['is_low'] == true ? Icons.warning_amber : Icons.check_circle_outline,
                        color: i['is_low'] == true ? Colors.orange : Colors.green),
                    title: Text(i['product_name']),
                    subtitle: Text(i['is_low'] == true ? 'स्टॉक कम है' : 'अपडेट: ${dateTime(parseTime(i['updated_at'])!)}'),
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
      title: const Text('स्टॉक बदलें'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: _product,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'प्रोडक्ट'),
            items: [for (final p in widget.products) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (v) => setState(() => _product = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'क्या हुआ?'),
            items: const [
              DropdownMenuItem(value: 'restock', child: Text('नया माल आया (+)')),
              DropdownMenuItem(value: 'wastage', child: Text('खराब / फेंका (−)')),
              DropdownMenuItem(value: 'adjustment', child: Text('गिनती सुधार (+/−)')),
            ],
            onChanged: (v) => setState(() => _reason = v!),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'मात्रा'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _low,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'कम स्टॉक की चेतावनी कब (ज़रूरी नहीं)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
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
          child: const Text('सेव'),
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
      appBar: AppBar(title: const Text('प्लान')),
      body: AsyncView(
        value: ref.watch(plansProvider),
        onRetry: () => ref.invalidate(plansProvider),
        data: (plans) => ListView(children: [
          if (current?['subscription'] != null)
            Card(
              color: Colors.green.shade50,
              child: ListTile(
                title: Text('अभी: ${current!['plan']['name']}'),
                subtitle: Text('${dateTime(parseTime(current['subscription']['ends_at'])!)} तक'),
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
                    Text(parseNum(p['price_monthly']) == 0 ? 'फ्री' : '${rupees(parseNum(p['price_monthly']))}/महीना',
                        style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 8),
                  Text('• ${p['max_active_deals'] ?? 'असीमित'} लाइव डील एक साथ'),
                  Text('• ${{'basic': 'बेसिक डील आंकड़े', 'sales': 'बिक्री रिपोर्ट', 'advanced': 'एडवांस रिपोर्ट'}[p['analytics']]}'),
                  if (p['priority_support'] == true) const Text('• प्राथमिकता सपोर्ट'),
                  if (p['featured_listing'] == true) const Text('• आपकी सारी डील सर्च में सबसे ऊपर ⭐'),
                  if (parseNum(p['price_monthly']) > 0) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        final api = ref.read(apiProvider);
                        final ok = await runAction(context, () async {
                          final sub = await api.post('/subscriptions/subscribe/', {'plan': p['code'], 'months': 1});
                          if (!context.mounted || !await payOnline(context, api, purpose: 'subscription', id: sub['id'])) {
                            throw ApiException('पेमेंट पूरा नहीं हुआ');
                          }
                        }, success: '${p['name']} प्लान चालू हो गया 🎉');
                        if (ok) ref.invalidate(currentPlanProvider);
                      },
                      child: Text(current?['plan']['code'] == p['code'] ? 'एक महीना और बढ़ाएं' : 'यह प्लान लें'),
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
      showMessage(context, 'पहले कोई डील लाइव करें');
      return;
    }
    Deal? deal = deals.first;
    var days = 1;
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('डील फीचर करें'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<Deal>(
              initialValue: deal,
              isExpanded: true,
              items: [for (final d in deals) DropdownMenuItem(value: d, child: Text(d.productName))],
              onChanged: (v) => setState(() => deal = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('कितने दिन'),
              const Spacer(),
              IconButton(onPressed: days > 1 ? () => setState(() => days--) : null, icon: const Icon(Icons.remove)),
              Text('$days'),
              IconButton(onPressed: days < 30 ? () => setState(() => days++) : null, icon: const Icon(Icons.add)),
            ]),
            Text('कीमत: ${rupees(49 * days)}'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('रद्द')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('पेमेंट करें')),
          ],
        ),
      ),
    );
    if (go != true || deal == null || !context.mounted) return;
    final api = ref.read(apiProvider);
    final ok = await runAction(context, () async {
      final ad = await api.post('/advertisements/create/', {'placement': 'featured_deal', 'deal': deal!.id, 'days': days});
      if (!context.mounted || !await payOnline(context, api, purpose: 'advertisement', id: ad['id'])) {
        throw ApiException('पेमेंट पूरा नहीं हुआ');
      }
    }, success: 'प्रमोशन चालू! आपकी डील सबसे ऊपर दिखेगी ⭐');
    if (ok) ref.invalidate(adsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('प्रमोशन')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _featureDeal(context, ref),
        icon: const Icon(Icons.campaign),
        label: const Text('डील फीचर करें'),
      ),
      body: AsyncView(
        value: ref.watch(adsProvider),
        onRetry: () => ref.invalidate(adsProvider),
        data: (ads) => ads.isEmpty
            ? const EmptyView(icon: Icons.campaign_outlined, message: 'फीचर्ड डील पास के ग्राहकों को सबसे ऊपर दिखती है। ₹49/दिन से शुरू।')
            : ListView(children: [
                for (final a in ads)
                  ListTile(
                    leading: Icon(a['placement'] == 'featured_deal' ? Icons.star : Icons.image),
                    title: Text(a['placement'] == 'featured_deal' ? 'फीचर्ड डील' : (a['title'] ?? 'बैनर')),
                    subtitle: Text('${a['days']} दिन · ${rupees(parseNum(a['price']))} · ${a['impressions']} बार दिखा, ${a['clicks']} क्लिक'),
                    trailing: Chip(label: Text({'active': 'चालू', 'pending_payment': 'पेमेंट बाकी', 'expired': 'खत्म', 'rejected': 'अस्वीकार'}[a['status']] ?? a['status'])),
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
      appBar: AppBar(title: const Text('ग्राहकों के रिव्यू')),
      body: AsyncView(
        value: ref.watch(merchantReviewsProvider),
        onRetry: () => ref.invalidate(merchantReviewsProvider),
        data: (reviews) => reviews.isEmpty
            ? const EmptyView(icon: Icons.star_outline, message: 'अभी कोई रिव्यू नहीं')
            : ListView(children: [
                for (final r in reviews)
                  Card(
                    child: ListTile(
                      leading: Stars(r.rating, size: 14),
                      title: Text(r.comment.isEmpty ? '(कोई टिप्पणी नहीं)' : r.comment),
                      subtitle: Text('${r.customerName} · ${dateTime(r.createdAt)}${r.reply.isEmpty ? '' : '\nआपका जवाब: ${r.reply}'}'),
                      isThreeLine: r.reply.isNotEmpty,
                      trailing: IconButton(
                        icon: const Icon(Icons.reply),
                        onPressed: () async {
                          final text = await askText(context, 'जवाब लिखें');
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
      appBar: AppBar(title: const Text('बिक्री और कमीशन')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const SectionTitle('पिछले 30 दिन की बिक्री'),
        sales.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(e is ApiException && e.code == 'upgrade_required' ? 'बिक्री रिपोर्ट Basic / Premium प्लान में है' : e.toString()),
              trailing: TextButton(onPressed: () => context.push('/merchant/plans'), child: const Text('प्लान देखें')),
            ),
          ),
          data: (s) {
            final daily = (s['daily'] as List).cast<Map<String, dynamic>>();
            final maxSale = daily.fold<double>(1, (m, d) => parseNum(d['sales']) > m ? parseNum(d['sales']) : m);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatTile(label: 'कुल बिक्री', value: rupees(parseNum(s['total_sales'])), icon: Icons.currency_rupee),
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
              const SectionTitle('सबसे ज़्यादा बिकने वाले'),
              for (final p in (s['top_products'] as List))
                ListTile(dense: true, title: Text(p['product']), trailing: Text(rupees(parseNum(p['sales'])))),
            ]);
          },
        ),
        const SectionTitle('प्लेटफ़ॉर्म कमीशन'),
        AsyncView(
          value: commission,
          data: (c) => Column(children: [
            ListTile(title: const Text('बकाया (अभी देना है)'), trailing: Text(rupees(parseNum(c['pending'])))),
            ListTile(title: const Text('चुका दिया'), trailing: Text(rupees(parseNum(c['settled'])))),
            ListTile(title: const Text('रिफंड के कारण वापस'), trailing: Text(rupees(parseNum(c['reversed'])))),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('हर पूरी हुई बिक्री पर एक छोटा कमीशन (जैसे 3%) लगता है। हिसाब हर हफ्ते होता है।'),
            ),
          ]),
        ),
      ]),
    );
  }
}
