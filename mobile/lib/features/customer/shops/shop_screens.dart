import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/shop_card.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/visuals.dart';
import '../../../core/config/app_config.dart';
import '../../chat/chat_screens.dart';
import '../daily/daily_screens.dart';
import '../customer_providers.dart';
import '../cart/cart_bar.dart';
import '../home/home_screen.dart';
import '../../../core/i18n/i18n.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(shopProvider(id)),
      onRetry: () => ref.invalidate(shopProvider(id)),
      data: (shop) {
        Future<void> toggleFavorite() async {
          final api = ref.read(apiProvider);
          final ok = await runAction(context, () async {
            shop.isFavorite ? await api.delete('/shops/$id/favorite/') : await api.post('/shops/$id/favorite/');
          }, success: shop.isFavorite ? tr('पसंदीदा से हटाया') : tr('पसंदीदा में जोड़ा — नई डील पर सूचना मिलेगी'));
          if (ok) {
            ref.invalidate(shopProvider(id));
            ref.invalidate(favoritesProvider);
          }
        }

        return Scaffold(
          bottomNavigationBar: const SafeArea(child: CartBar()),
          body: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 220,
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
              title: Text(shop.name, style: const TextStyle(color: Colors.white)),
              actions: [
                IconButton(
                  tooltip: tr('पसंदीदा'),
                  icon: Icon(shop.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: shop.isFavorite ? const Color(0xFFFF4D6D) : Colors.white),
                  onPressed: toggleFavorite,
                ),
                IconButton(
                  tooltip: tr('WhatsApp पर शेयर'),
                  icon: const Icon(Icons.share_rounded, color: Colors.white),
                  onPressed: () => launchUrl(
                    Uri.parse('https://wa.me/?text=${Uri.encodeComponent('${shop.name} — ${tr('आज की ताज़ा डील')}\n${AppConfig.siteUrl}/s/${shop.id}/')}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const CartIconButton(color: Colors.white),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  Hero(
                    tag: 'shop-cover-${shop.id}',
                    child: shop.coverImage != null
                        ? CachedNetworkImage(imageUrl: shop.coverImage!, fit: BoxFit.cover)
                        : ProductArt(name: shop.name, category: shop.categoryName, size: double.infinity),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black45, Colors.transparent, Colors.black54],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(shop.name, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.ink)),
                    ),
                    RatingBadge(shop.rating, count: shop.ratingCount),
                  ]),
                  const SizedBox(height: 4),
                  Text('${shop.categoryName} · ${shop.address}', style: TextStyle(color: AppTheme.muted)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (shop.qualityAssured) QualityBadge(shop: shop, large: true),
                    _InfoPill(icon: Icons.bolt_rounded, text: tr('{0} मिनट', [shop.prepMinutes]), color: const Color(0xFFF59E0B)),
                    if (shop.distanceM != null)
                      _InfoPill(icon: Icons.near_me_rounded, text: distance(shop.distanceM), color: AppTheme.primary),
                    if (shop.liveDealsCount > 0)
                      _InfoPill(
                        icon: Icons.local_fire_department_rounded,
                        text: tr('{0} डील लाइव', [shop.liveDealsCount]),
                        color: AppTheme.deal,
                      ),
                    if (shop.offersDelivery)
                      _InfoPill(icon: Icons.delivery_dining_rounded, text: tr('होम डिलीवरी'), color: const Color(0xFF2563EB)),
                  ]),
                  const SizedBox(height: 14),
                  ContactActions(phone: shop.phone, latitude: shop.latitude, longitude: shop.longitude),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: const StadiumBorder()),
                        onPressed: () => startChat(context, ref, shop.id),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                        label: Text(tr('चैट करें')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                        onPressed: () => showSubscribeSheet(context, shop),
                        icon: const Icon(Icons.event_repeat_rounded, size: 18),
                        label: Text(tr('रोज़ मंगवाएं')),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            SliverToBoxAdapter(child: SectionTitle(tr('अभी की डील'))),
            ref.watch(shopDealsProvider(id)).when(
                  loading: () => const SliverToBoxAdapter(child: DealListSkeleton(count: 2)),
                  error: (e, _) => SliverToBoxAdapter(child: ErrorView(message: e.toString())),
                  data: (deals) => deals.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(padding: const EdgeInsets.all(16), child: Text(tr('अभी कोई लाइव डील नहीं।'))),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.66,
                            ),
                            itemCount: deals.length,
                            itemBuilder: (_, i) => DealGridCard(
                              deal: deals[i],
                              index: i,
                              onAdd: () => quickAdd(context, ref, deals[i]),
                              onTap: () => context.push('/deal/${deals[i].id}'),
                            ),
                          ),
                        ),
                ),
            SliverToBoxAdapter(child: SectionTitle(tr('रिव्यू'))),
            SliverToBoxAdapter(
              child: AsyncView(
                value: ref.watch(shopReviewsProvider(id)),
                data: (reviews) => reviews.isEmpty
                    ? Padding(padding: const EdgeInsets.all(16), child: Text(tr('अभी कोई रिव्यू नहीं।')))
                    : Column(children: [
                        for (final r in reviews)
                          ListTile(
                            leading: Stars(r.rating, size: 14),
                            title: Text(r.comment.isEmpty ? '—' : r.comment),
                            subtitle: Text(
                                '${r.customerName} · ${dateTime(r.createdAt)}${r.reply.isEmpty ? '' : tr('\nदुकान: {0}', [r.reply])}'),
                            trailing: r.photo == null
                                ? null
                                : GestureDetector(
                                    onTap: () => showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        clipBehavior: Clip.antiAlias,
                                        child: CachedNetworkImage(imageUrl: r.photo!, fit: BoxFit.contain),
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(imageUrl: r.photo!, width: 56, height: 56, fit: BoxFit.cover),
                                    ),
                                  ),
                          ),
                      ]),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ]),
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      );
}

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('पसंदीदा दुकानें'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(favoritesProvider.future),
        child: AsyncView(
          value: ref.watch(favoritesProvider),
          onRetry: () => ref.invalidate(favoritesProvider),
          data: (shops) => shops.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 120),
                  EmptyView(icon: Icons.favorite_border, message: tr('दुकान पेज पर ♥ दबाएं — उनकी नई डील की सूचना सबसे पहले मिलेगी')),
                ])
              : ListView(children: [
                  for (final s in shops)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.storefront),
                        title: Text(s.name),
                        subtitle: Text(s.address),
                        trailing: s.ratingCount > 0 ? Text('★ ${s.rating.toStringAsFixed(1)}') : null,
                        onTap: () => context.push('/shop/${s.id}'),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}
