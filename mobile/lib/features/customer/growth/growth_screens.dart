import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/prefs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../../shared/widgets/motion.dart';
import '../cart/cart.dart';
import '../cart/cart_bar.dart';
import '../home/home_screen.dart';

// ---------------- price alerts ----------------

final alertsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.watch(apiProvider).get('/growth/alerts/') as List;
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

/// "Tell me when paneer is below ₹300."
Future<void> addPriceAlert(BuildContext context, WidgetRef ref, {String query = ''}) async {
  final what = TextEditingController(text: query);
  final price = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AppDialog(
      title: tr('दाम गिरने पर बताएं'),
      icon: Icons.notifications_active_outlined,
      message: tr('जैसे ही पास की किसी दुकान पर इससे कम दाम में डील आएगी, आपको सूचना मिलेगी।'),
      body: Column(children: [
        TextField(controller: what, decoration: InputDecoration(hintText: tr('क्या? (जैसे paneer, टमाटर)'), filled: true, fillColor: AppTheme.chip)),
        const SizedBox(height: 10),
        TextField(
          controller: price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          decoration: InputDecoration(prefixText: '₹ ', hintText: tr('इससे कम दाम पर'), filled: true, fillColor: AppTheme.chip),
        ),
      ]),
      okLabel: tr('अलर्ट लगाएं'),
      cancelLabel: tr('रद्द'),
      onOk: () => Navigator.pop(dialog, true),
    ),
  );
  if (ok != true || what.text.trim().isEmpty || price.text.trim().isEmpty || !context.mounted) return;
  final here = await ref.read(locationProvider.future);
  if (!context.mounted) return;
  final saved = await runAction(context, () => ref.read(apiProvider).post('/growth/alerts/', {
        'query': what.text.trim(),
        'max_price': price.text.trim(),
        'latitude': here.latitude.toStringAsFixed(6),
        'longitude': here.longitude.toStringAsFixed(6),
      }), success: tr('अलर्ट लग गया 🔔'));
  if (saved) ref.invalidate(alertsProvider);
}

class PriceAlertsScreen extends ConsumerWidget {
  const PriceAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('दाम अलर्ट'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'alert-add',
        onPressed: () => addPriceAlert(context, ref),
        icon: const Icon(Icons.add_alert_outlined),
        label: Text(tr('नया अलर्ट')),
      ),
      body: AsyncView(
        value: ref.watch(alertsProvider),
        onRetry: () => ref.invalidate(alertsProvider),
        data: (rows) => rows.isEmpty
            ? EmptyView(icon: Icons.notifications_none_rounded, message: tr('कोई अलर्ट नहीं।\n"नया अलर्ट" से बताएं क्या और किस दाम पर चाहिए।'))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                for (final a in rows)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.chip,
                        child: Icon(Icons.notifications_active_outlined, color: AppTheme.accentInk),
                      ),
                      title: Text(a['query'], style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(tr('{0} से कम होने पर', [rupees(parseNum(a['max_price']))])),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          if (await runAction(context, () => ref.read(apiProvider).delete('/growth/alerts/${a['id']}/'))) {
                            ref.invalidate(alertsProvider);
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

// ---------------- shopping list ----------------

const _listKey = 'shopping_list';

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  late final _text = TextEditingController(text: Prefs.get(_listKey) ?? '');
  Map<String, dynamic>? _result;
  bool _busy = false;

  Future<void> _find() async {
    final items = _text.text.split(RegExp(r'[,\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (items.isEmpty) return;
    await Prefs.set(_listKey, _text.text);
    setState(() => _busy = true);
    final here = await ref.read(locationProvider.future);
    if (!mounted) return;
    await runAction(context, () async {
      final data = await ref.read(apiProvider).post('/growth/shopping-list/', {
        'items': items,
        'latitude': here.latitude.toStringAsFixed(6),
        'longitude': here.longitude.toStringAsFixed(6),
      });
      _result = Map<String, dynamic>.from(data);
    });
    if (mounted) setState(() => _busy = false);
  }

  void _addAll(List<Deal> deals) {
    final cart = ref.read(cartProvider.notifier);
    cart.clear();
    for (final d in deals) {
      cart.add(d, ['kg', 'litre'].contains(d.unit) ? 0.5 : 1);
    }
    showMessage(context, tr('{0} चीज़ें कार्ट में डालीं', [deals.length]));
  }

  @override
  Widget build(BuildContext context) {
    final best = _result?['best_shop'] as Map?;
    final bestDeals = best == null ? <Deal>[] : [for (final d in best['deals'] as List) Deal.fromJson(Map<String, dynamic>.from(d))];
    return Scaffold(
      appBar: AppBar(title: Text(tr('शॉपिंग लिस्ट'))),
      bottomNavigationBar: const SafeArea(child: CartBar()),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _text,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: tr('हर लाइन में एक चीज़ लिखें:\ndoodh\nbread\nटमाटर'),
            filled: true,
            fillColor: AppTheme.chip,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _find,
          icon: const Icon(Icons.manage_search_rounded),
          label: Text(tr('सबसे सस्ता ढूंढें')),
        ),
        if (best != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('एक ही दुकान से सबसे ज़्यादा'), style: const TextStyle(color: Colors.white70)),
              Text(best['name'], style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              Text(tr('{0} में से {1} चीज़ें · {2}', [best['of'], best['covers'], rupees(parseNum(best['total']))]),
                  style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.minimal ? AppTheme.accent : Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => _addAll(bestDeals),
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: Text(tr('सब कार्ट में डालें')),
              ),
            ]),
          ),
        ],
        for (final row in (_result?['items'] as List? ?? const [])) ...[
          SectionTitle(row['item']),
          if ((row['deals'] as List).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                Expanded(child: Text(tr('पास में अभी डील नहीं'), style: TextStyle(color: AppTheme.muted))),
                TextButton.icon(
                  onPressed: () => addPriceAlert(context, ref, query: row['item']),
                  icon: const Icon(Icons.add_alert_outlined, size: 18),
                  label: Text(tr('अलर्ट लगाएं')),
                ),
              ]),
            ),
          for (final d in [for (final x in row['deals'] as List) Deal.fromJson(Map<String, dynamic>.from(x))])
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push('/deal/${d.id}'),
              leading: ClipRRect(borderRadius: BorderRadius.circular(12), child: DealImage(d.image, size: 52, name: d.productName, category: d.categoryName)),
              title: Text(d.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(d.shop.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${rupees(d.offerPrice)}/${unitLabel(d.unit)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                AddStepper(deal: d, onAdd: () => quickAdd(context, ref, d)),
              ]),
            ),
        ],
      ]),
    );
  }
}

// ---------------- loyalty ----------------

final loyaltyProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async => Map<String, dynamic>.from(await ref.watch(apiProvider).get('/growth/loyalty/')),
);

class LoyaltyScreen extends ConsumerWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('पॉइंट और स्ट्रीक'))),
      body: AsyncView(
        value: ref.watch(loyaltyProvider),
        onRetry: () => ref.invalidate(loyaltyProvider),
        data: (d) {
          final points = d['points'] as int;
          final streak = d['streak_days'] as int;
          final target = d['streak_target'] as int;
          final unit = d['redeem_unit'] as int;
          final canRedeem = points ~/ unit * unit;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(24)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('आपके पॉइंट'), style: const TextStyle(color: Colors.white70)),
                Text('$points', style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
                Text(tr('{0} पॉइंट = ₹{1} वॉलेट में · हर ₹10 की खरीद पर 1 पॉइंट', [unit, d['redeem_value']]),
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.minimal ? AppTheme.accent : Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: canRedeem == 0
                      ? null
                      : () async {
                          final ok = await runAction(context, () => ref.read(apiProvider).post('/growth/loyalty/', {'points': canRedeem}),
                              success: tr('₹{0} वॉलेट में आ गए', [canRedeem ~/ unit * (d['redeem_value'] as int)]));
                          if (ok) ref.invalidate(loyaltyProvider);
                        },
                  child: Text(canRedeem == 0 ? tr('{0} पॉइंट होने पर बदलें', [unit]) : tr('{0} पॉइंट वॉलेट में बदलें', [canRedeem])),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('🔥', style: TextStyle(fontSize: 26)),
                    const SizedBox(width: 8),
                    Text(tr('{0} दिन की स्ट्रीक', [streak]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 4),
                  Text(tr('लगातार {0} दिन खरीदें, {1} बोनस पॉइंट पाएं', [target, d['streak_bonus']]), style: TextStyle(color: AppTheme.muted)),
                  const SizedBox(height: 12),
                  Row(children: [
                    for (var i = 0; i < target; i++)
                      Expanded(
                        child: Container(
                          height: 10,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: i < streak % target || (streak > 0 && streak % target == 0) ? AppTheme.accent : AppTheme.chip,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Text(tr('सबसे लंबी स्ट्रीक: {0} दिन', [d['best_streak']]), style: TextStyle(fontSize: 12, color: AppTheme.muted)),
                ]),
              ),
            ),
            SectionTitle(tr('हिसाब')),
            for (final e in (d['entries'] as List).cast<Map>())
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  e['kind'] == 'redeem' ? Icons.account_balance_wallet_outlined : e['kind'] == 'streak' ? Icons.local_fire_department_rounded : Icons.shopping_bag_outlined,
                  color: e['kind'] == 'redeem' ? AppTheme.muted : AppTheme.accentInk,
                ),
                title: Text(switch (e['kind']) { 'redeem' => tr('वॉलेट में बदले'), 'streak' => tr('स्ट्रीक बोनस'), _ => tr('खरीद') }),
                subtitle: Text('${e['reference'] ?? ''}'),
                trailing: Text('${(e['points'] as int) > 0 ? '+' : ''}${e['points']}',
                    style: TextStyle(fontWeight: FontWeight.w900, color: (e['points'] as int) > 0 ? AppTheme.accentInk : AppTheme.muted)),
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------- mohalla group deals ----------------

final groupsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final here = await ref.watch(locationProvider.future);
  final rows = await ref.watch(apiProvider).get('/growth/groups/', query: {
    'latitude': here.latitude.toStringAsFixed(6),
    'longitude': here.longitude.toStringAsFixed(6),
  }) as List;
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

Future<void> joinGroup(BuildContext context, WidgetRef ref, Map g) async {
  Map<String, dynamic>? after;
  final ok = await runAction(context, () async {
    after = Map<String, dynamic>.from(await ref.read(apiProvider).post('/growth/groups/${g['id']}/join/'));
  });
  if (!ok || !context.mounted) return;
  ref.invalidate(groupsProvider);
  final deal = Deal.fromJson(Map<String, dynamic>.from(after!['deal']));
  if (after!['unlocked'] == true) {
    showMessage(context, tr('डील खुल गई! अब खरीदें, {0}% वापस मिलेगा', [after!['extra_percent']]));
    return;
  }
  final left = (after!['target'] as int) - (after!['members'] as int);
  final share = await confirm(context, tr('आप जुड़ गए! बस {0} लोग और चाहिए', [left]),
      message: tr('दोस्तों और पड़ोसियों को WhatsApp पर बुलाएं — सबको {0}% और मिलेगा।', [after!['extra_percent']]),
      ok: tr('WhatsApp पर बुलाएं'), icon: Icons.groups_rounded);
  if (share) {
    final text = '${tr('मोहल्ला डील')}: ${deal.productName} — ${deal.shop.name}. '
        '${tr('{0} लोग जुड़ें तो सबको {1}% और छूट!', [after!['target'], after!['extra_percent']])}\n${AppConfig.siteUrl}/d/${deal.id}/';
    launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }
}

/// Home section: mohalla deals with join progress.
class GroupDealsStrip extends ConsumerWidget {
  const GroupDealsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).value ?? const [];
    if (groups.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(tr('मोहल्ला डील — साथ खरीदें, ज़्यादा बचाएं')),
      SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final g = groups[i];
            final deal = Deal.fromJson(Map<String, dynamic>.from(g['deal']));
            final members = g['members'] as int, target = g['target'] as int;
            return Container(
              width: 250,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow(0.05)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: DealImage(deal.image, size: 44, name: deal.productName, category: deal.categoryName)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(deal.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(tr('+{0}% और वापस', [g['extra_percent']]), style: TextStyle(color: AppTheme.accentInk, fontWeight: FontWeight.w800, fontSize: 12)),
                    ]),
                  ),
                ]),
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: (members / target).clamp(0, 1).toDouble(), minHeight: 8, color: AppTheme.accent, backgroundColor: AppTheme.chip),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(g['unlocked'] == true ? tr('खुल गई! 🎉') : tr('{0}/{1} लोग जुड़े', [members, target]),
                        style: TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w700)),
                  ),
                  if (g['joined'] == true)
                    TextButton(onPressed: () => context.push('/deal/${deal.id}'), child: Text(g['unlocked'] == true ? tr('खरीदें') : tr('जुड़ गए ✓')))
                  else
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: () => joinGroup(context, ref, g),
                      child: Text(tr('जुड़ें')),
                    ),
                ]),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

// ---------------- festival campaigns ----------------

final campaignsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.watch(apiProvider).get('/growth/campaigns/') as List;
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

Color _hex(String? value) {
  final v = (value ?? '').replaceAll('#', '');
  return v.length == 6 ? Color(int.parse('FF$v', radix: 16)) : const Color(0xFF0A0A0A);
}

/// Home banner for a running festival campaign (with its coupon code).
class CampaignBanner extends ConsumerWidget {
  const CampaignBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(campaignsProvider).value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final c = list.first;
    final color = _hex(c['color']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: FadeSlideIn(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            image: c['image'] == null
                ? null
                : DecorationImage(image: NetworkImage(c['image']), fit: BoxFit.cover, colorFilter: ColorFilter.mode(color.withValues(alpha: 0.55), BlendMode.srcATop)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['title'], style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                if ((c['subtitle'] ?? '').isNotEmpty) Text(c['subtitle'], style: const TextStyle(color: Colors.white)),
              ]),
            ),
            if (c['coupon'] != null)
              Pressable(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: c['coupon']));
                  showMessage(context, tr('कूपन {0} कॉपी हुआ — कार्ट में लगाएं', [c['coupon']]));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Text(c['coupon'], style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, color: color)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
