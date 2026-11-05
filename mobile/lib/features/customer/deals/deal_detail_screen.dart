import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../../shared/widgets/motion.dart';
import '../cart/cart.dart';
import '../customer_providers.dart';

Future<void> openDirections(double lat, double lng) =>
    launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'), mode: LaunchMode.externalApplication);

class DealDetailScreen extends ConsumerWidget {
  const DealDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(dealProvider(id)).when(
          loading: () => Scaffold(
            appBar: AppBar(),
            body: Hero(
              tag: 'deal-image-$id',
              child: const AspectRatio(aspectRatio: 1.2, child: Shimmer(child: SkeletonBox(height: 300, radius: 0))),
            ),
          ),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: ErrorView(message: e.toString(), onRetry: () => ref.invalidate(dealProvider(id))),
          ),
          data: (deal) => _DealBody(deal: deal),
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
  DateTime? _pickupAt; // null = within 45 minutes

  Deal get deal => widget.deal;

  // Loose items (kg, litre) can be bought in halves; the rest in whole units.
  double get _step => (deal.unit == 'kg' || deal.unit == 'litre') ? 0.5 : 1;

  Future<void> _reserve() async {
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    Map<String, dynamic>? created;
    await runAction(context, () async {
      created = Map<String, dynamic>.from(await ref.read(apiProvider).post('/reservations/create/', {
        'deal': deal.id,
        'quantity': _qty.toStringAsFixed(2),
        if (_pickupAt != null) 'pickup_at': _pickupAt!.toUtc().toIso8601String(),
      }));
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (created != null) {
      ref.invalidate(myReservationsProvider);
      context.pushReplacement('/success', extra: {'route': '/reservation/${created!['id']}', 'order': false});
    }
  }

  Future<void> _addToCart() async {
    HapticFeedback.lightImpact();
    final cart = ref.read(cartProvider.notifier);
    if (!cart.add(deal, _qty)) {
      final replace = await confirm(context, tr('कार्ट में दूसरी दुकान का सामान है'),
          message: tr('एक ऑर्डर में एक ही दुकान का सामान आ सकता है। पुराना कार्ट हटा कर यह डालें?'), ok: tr('हाँ, बदलें'));
      if (!replace) return;
      cart.replaceWith(deal, _qty);
    }
    if (mounted) showMessage(context, tr('कार्ट में जोड़ा गया'));
  }

  Future<void> _pickCustomTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (now.hour + 1) % 24, minute: 0));
    if (picked == null || !mounted) return;
    final today = DateTime.now();
    var at = DateTime(today.year, today.month, today.day, picked.hour, picked.minute);
    if (at.isBefore(today)) at = at.add(const Duration(days: 1));
    if (at.isAfter(deal.expiresAt)) {
      showMessage(context, tr('डील {0} तक है, उससे पहले का समय चुनें', [timeOnly(deal.expiresAt)]));
      return;
    }
    setState(() => _pickupAt = at);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = deal.offerPrice * _qty;
    final saved = (deal.normalPrice - deal.offerPrice) * _qty;
    final quickSlots = [
      for (final minutes in [60, 120, 180])
        if (DateTime.now().add(Duration(minutes: minutes)).isBefore(deal.expiresAt)) minutes,
    ];

    return Scaffold(
      bottomNavigationBar: deal.isLive
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(color: AppTheme.card, boxShadow: AppTheme.softShadow(0.1)),
                child: Row(children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(56, 52), padding: EdgeInsets.zero),
                    onPressed: _addToCart,
                    child: const Icon(Icons.add_shopping_cart_rounded),
                  ),
                  const SizedBox(width: 10),
                  if (deal.canPickup)
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(14)),
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
                          onPressed: _busy ? null : _reserve,
                          child: _busy
                              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Text('${tr('रिज़र्व करें · दुकान पर पैसे दें')}  ${rupees(total)}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: FilledButton(onPressed: _addToCart, child: Text(tr('कार्ट में डालें (ऑनलाइन पेमेंट)'))),
                    ),
                ]),
              ),
            )
          : null,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: 320,
          backgroundColor: Colors.white,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              backgroundColor: AppTheme.card,
              child: IconButton(icon: Icon(Icons.arrow_back_rounded, color: AppTheme.ink), onPressed: () => context.pop()),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground],
            background: Stack(fit: StackFit.expand, children: [
              Hero(tag: 'deal-image-${deal.id}', child: DealImage(deal.image, size: double.infinity, name: deal.productName, category: deal.categoryName)),
              Positioned(left: 16, bottom: 16, child: DiscountBadge(deal.discountPercent, large: true)),
              if (deal.isFeatured)
                Positioned(
                  right: 16,
                  bottom: 18,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.featured, borderRadius: BorderRadius.circular(20)),
                    child: Text(tr('⭐ फीचर्ड'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FadeSlideIn(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(deal.productName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  StatusChip(deal.status),
                ]),
              ),
              const SizedBox(height: 8),
              FadeSlideIn(index: 1, child: PriceLine(offer: deal.offerPrice, normal: deal.normalPrice, unit: deal.unit, large: true)),
              const SizedBox(height: 10),
              FadeSlideIn(
                index: 2,
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  CountdownChip(deal.expiresAt),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(tr('{0}% की बचत', [deal.discountPercent.round()]),
                        style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.chip, borderRadius: BorderRadius.circular(20)),
                    child: Text('${qty(deal.quantityAvailable)} ${unitLabel(deal.unit)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ]),
              ),
              if (deal.description.isNotEmpty) ...[
                const SizedBox(height: 14),
                FadeSlideIn(index: 3, child: Text(deal.description, style: theme.textTheme.bodyLarge)),
              ],
              const SizedBox(height: 16),
              FadeSlideIn(
                index: 4,
                child: Pressable(
                  onTap: () => context.push('/shop/${deal.shop.id}'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.card, borderRadius: AppTheme.radius, boxShadow: AppTheme.softShadow(0.05)),
                    child: Row(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.storefront_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(deal.shop.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text(deal.shop.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                          if (deal.shop.ratingCount > 0)
                            Row(children: [Stars(deal.shop.rating, size: 14), Text('  ${deal.shop.rating.toStringAsFixed(1)}')]),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FadeSlideIn(
                index: 5,
                child: ContactActions(
                  phone: deal.shop.phone,
                  latitude: deal.shop.latitude,
                  longitude: deal.shop.longitude,
                  message: '${deal.productName} — Micro Bargain',
                ),
              ),
              if (deal.isLive) ...[
                const SizedBox(height: 20),
                FadeSlideIn(
                  index: 5,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppTheme.card, borderRadius: AppTheme.radius),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(tr('मात्रा'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        _StepButton(icon: Icons.remove_rounded, onTap: _qty > _step ? () => setState(() => _qty -= _step) : null),
                        SizedBox(
                          width: 92,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                            child: Text('${qty(_qty)} ${unitLabel(deal.unit)}',
                                key: ValueKey(_qty),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        _StepButton(
                          icon: Icons.add_rounded,
                          onTap: _qty + _step <= deal.quantityAvailable ? () => setState(() => _qty += _step) : null,
                        ),
                      ]),
                      const Divider(height: 24),
                      Text(tr('कुल {0} · आपकी बचत {1}', [rupees(total), rupees(saved)]),
                          style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.primaryDark, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                if (deal.canPickup) ...[
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    index: 6,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppTheme.card, borderRadius: AppTheme.radius),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.schedule_rounded, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Text(tr('कब लेने आएंगे?'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          ChoiceChip(
                            label: Text(tr('अभी (45 मिनट में)')),
                            selected: _pickupAt == null,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _pickupAt = null),
                          ),
                          for (final minutes in quickSlots)
                            ChoiceChip(
                              label: Text(timeOnly(DateTime.now().add(Duration(minutes: minutes)))),
                              selected: _pickupAt != null && (_pickupAt!.difference(DateTime.now()).inMinutes - minutes).abs() < 2,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _pickupAt = DateTime.now().add(Duration(minutes: minutes))),
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.edit_calendar_rounded, size: 18),
                            label: Text(_pickupAt != null && !quickSlots.any((m) => (_pickupAt!.difference(DateTime.now()).inMinutes - m).abs() < 2)
                                ? timeOnly(_pickupAt!)
                                : tr('समय चुनें')),
                            onPressed: _pickCustomTime,
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          _pickupAt == null
                              ? tr('रिज़र्व करने पर सामान 45 मिनट तक आपके लिए रखा जाएगा। दुकान पर पिकअप कोड बताकर पैसे दें।')
                              : tr('सामान {0} तक आपके लिए रखा रहेगा। दुकान पर पिकअप कोड बताकर पैसे दें।',
                                  [timeOnly(_pickupAt!.add(const Duration(minutes: 30)))]),
                          style: theme.textTheme.bodySmall,
                        ),
                      ]),
                    ),
                  ),
                ],
              ] else
                Padding(padding: const EdgeInsets.only(top: 20), child: Text(tr('यह डील अब उपलब्ध नहीं है।'))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: onTap == null ? 0.35 : 1,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      );
}
