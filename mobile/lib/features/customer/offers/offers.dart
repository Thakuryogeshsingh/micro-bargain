import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';

/// Coupons the customer can use now: all of them, or only those valid at one shop.
final offersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, int?>((ref, shopId) async {
  final data = await ref.watch(apiProvider).get('/orders/offers/', query: {'shop': shopId});
  return (data as List).cast<Map<String, dynamic>>();
});

String offerTitle(Map<String, dynamic> o) => o['discount_type'] == 'percent'
    ? tr('{0}% छूट', [parseNum(o['value']).round()])
    : tr('₹{0} छूट', [parseNum(o['value']).round()]);

String offerCondition(Map<String, dynamic> o) {
  final parts = <String>[
    if (parseNum(o['min_order_amount']) > 0) tr('₹{0} से ऊपर', [parseNum(o['min_order_amount']).round()]),
    if (o['max_discount'] != null) tr('ज़्यादा से ज़्यादा ₹{0}', [parseNum(o['max_discount']).round()]),
    if (o['first_order_only'] == true) tr('सिर्फ पहला ऑर्डर'),
    if (o['shop_name'] != null) o['shop_name'] as String,
  ];
  return parts.join(' · ');
}

/// A ticket-shaped coupon card.
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.offer, this.onTap, this.width = 250, this.actionLabel});

  final Map<String, dynamic> offer;
  final VoidCallback? onTap;
  final double width;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final personal = offer['is_personal'] == true;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          gradient: personal
              ? const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFDB2777)])
              : AppTheme.dealGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppTheme.softShadow(0.12),
        ),
        child: Stack(children: [
          Positioned(right: -18, top: -18, child: CircleAvatar(radius: 40, backgroundColor: Colors.white.withValues(alpha: 0.12))),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(personal ? Icons.card_giftcard_rounded : Icons.local_offer_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(offerTitle(offer),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(offerCondition(offer),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
              const Spacer(),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.card.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white54),
                  ),
                  child: Text(offer['code'],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ),
                const Spacer(),
                Text(actionLabel ?? tr('कॉपी करें'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Horizontal list of offers for the home screen; tapping copies the code.
class OffersStrip extends ConsumerWidget {
  const OffersStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(offersProvider(null)).value ?? [];
    if (offers.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(tr('ऑफ़र'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ),
      SizedBox(
        height: 156,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: offers.length,
          itemBuilder: (context, i) => FadeSlideIn(
            index: i,
            offset: 0.2,
            child: OfferCard(
              offer: offers[i],
              onTap: () {
                Clipboard.setData(ClipboardData(text: offers[i]['code']));
                showMessage(context, tr('कूपन {0} कॉपी हुआ — कार्ट में लगाएं', [offers[i]['code']]));
              },
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Bottom sheet listing the offers valid at a shop; returns the chosen code.
Future<String?> pickOffer(BuildContext context, int shopId) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Consumer(builder: (context, ref, _) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: AsyncView(
            value: ref.watch(offersProvider(shopId)),
            data: (offers) => offers.isEmpty
                ? EmptyView(icon: Icons.local_offer_outlined, message: tr('अभी कोई ऑफ़र नहीं'))
                : ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(10, 0, 10, 16), children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(tr('ऑफ़र'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    for (var i = 0; i < offers.length; i++)
                      FadeSlideIn(
                        index: i,
                        child: SizedBox(
                          height: 146,
                          child: OfferCard(
                            offer: offers[i],
                            width: double.infinity,
                            actionLabel: tr('लगाएं'),
                            onTap: () => Navigator.pop(context, offers[i]['code'] as String),
                          ),
                        ),
                      ),
                  ]),
          ),
        ),
      );
    }),
  );
}

// ---------- referral ----------

final _referralProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/customers/referral/'));
});

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _friendCode = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('दोस्तों को बुलाएं'))),
      body: AsyncView(
        value: ref.watch(_referralProvider),
        onRetry: () => ref.invalidate(_referralProvider),
        data: (r) => ListView(padding: const EdgeInsets.all(16), children: [
          FadeSlideIn(
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFDB2777)]),
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.softShadow(0.2),
              ),
              child: Column(children: [
                const Text('🎁', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 8),
                Text(
                  tr('दोस्त को बुलाएं, दोनों पाएं ₹{0}', [r['reward_amount']]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  tr('दोस्त आपके कोड से जुड़े और पहली खरीद करे, तो दोनों को ₹{0} का कूपन (₹{1} से ऊपर के ऑर्डर पर)',
                      [r['reward_amount'], r['min_order']]),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 18),
                Pressable(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: r['code']));
                    showMessage(context, tr('कोड कॉपी हुआ'));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(r['code'],
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, color: Color(0xFF7C3AED))),
                      const SizedBox(width: 10),
                      const Icon(Icons.copy_rounded, color: Color(0xFF7C3AED)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          FadeSlideIn(
            index: 1,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              onPressed: () => launchUrl(
                Uri.parse('https://wa.me/?text=${Uri.encodeComponent(r['share_text'])}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.share_rounded),
              label: Text(tr('WhatsApp पर शेयर करें')),
            ),
          ),
          const SizedBox(height: 16),
          FadeSlideIn(
            index: 2,
            child: Row(children: [
              Expanded(
                child: StatTile(label: tr('जुड़े दोस्त'), value: parseNum(r['friends_joined']), icon: Icons.group_add_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: tr('मिला इनाम'),
                  value: parseNum(r['friends_rewarded']) * parseNum(r['reward_amount']),
                  format: rupees,
                  icon: Icons.redeem_rounded,
                  color: const Color(0xFFDB2777),
                ),
              ),
            ]),
          ),
          if (r['referred_by_applied'] != true) ...[
            const SizedBox(height: 24),
            FadeSlideIn(
              index: 3,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(tr('किसी दोस्त ने बुलाया है?'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _friendCode,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(labelText: tr('दोस्त का रेफ़रल कोड (अगर है)')),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await runAction(
                          context,
                          () => ref.read(apiProvider).post('/customers/referral/', {'code': _friendCode.text.trim()}),
                          success: tr('रेफ़रल कोड लग गया! पहली खरीद पर इनाम मिलेगा'),
                        );
                        if (ok) ref.invalidate(_referralProvider);
                      },
                      child: Text(tr('लगाएं')),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
