import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/deal_card.dart';
import '../customer_providers.dart';
import '../../../core/i18n/i18n.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(shopProvider(id)),
      onRetry: () => ref.invalidate(shopProvider(id)),
      data: (shop) => Scaffold(
        appBar: AppBar(title: Text(shop.name), actions: [
          IconButton(
            tooltip: tr('पसंदीदा'),
            icon: Icon(shop.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.red),
            onPressed: () async {
              final api = ref.read(apiProvider);
              final ok = await runAction(context, () async {
                shop.isFavorite ? await api.delete('/shops/$id/favorite/') : await api.post('/shops/$id/favorite/');
              }, success: shop.isFavorite ? tr('पसंदीदा से हटाया') : tr('पसंदीदा में जोड़ा — नई डील पर सूचना मिलेगी'));
              if (ok) {
                ref.invalidate(shopProvider(id));
                ref.invalidate(favoritesProvider);
              }
            },
          ),
        ]),
        body: ListView(children: [
          ListTile(
            title: Text(shop.categoryName),
            subtitle: Text(shop.address),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ContactActions(phone: shop.phone, latitude: shop.latitude, longitude: shop.longitude),
          ),
          if (shop.ratingCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [Stars(shop.rating), Text(tr('  {0} ({1} रिव्यू)', [shop.rating.toStringAsFixed(1), shop.ratingCount]))]),
            ),
          SectionTitle(tr('अभी की डील')),
          AsyncView(
            value: ref.watch(shopDealsProvider(id)),
            data: (deals) => deals.isEmpty
                ? Padding(padding: const EdgeInsets.all(16), child: Text(tr('अभी कोई लाइव डील नहीं।')))
                : Column(children: [for (final d in deals) DealCard(deal: d, onTap: () => context.push('/deal/${d.id}'))]),
          ),
          SectionTitle(tr('रिव्यू')),
          AsyncView(
            value: ref.watch(shopReviewsProvider(id)),
            data: (reviews) => reviews.isEmpty
                ? Padding(padding: const EdgeInsets.all(16), child: Text(tr('अभी कोई रिव्यू नहीं।')))
                : Column(children: [
                    for (final r in reviews)
                      ListTile(
                        leading: Stars(r.rating, size: 14),
                        title: Text(r.comment.isEmpty ? '—' : r.comment),
                        subtitle: Text('${r.customerName} · ${dateTime(r.createdAt)}${r.reply.isEmpty ? '' : tr('\nदुकान: {0}', [r.reply])}'),
                      ),
                  ]),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
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
