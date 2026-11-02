import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../customer_providers.dart';
import '../deals/deal_detail_screen.dart';

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
            tooltip: 'पसंदीदा',
            icon: Icon(shop.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.red),
            onPressed: () async {
              final api = ref.read(apiProvider);
              final ok = await runAction(context, () async {
                shop.isFavorite ? await api.delete('/shops/$id/favorite/') : await api.post('/shops/$id/favorite/');
              }, success: shop.isFavorite ? 'पसंदीदा से हटाया' : 'पसंदीदा में जोड़ा — नई डील पर सूचना मिलेगी');
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
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (shop.phone.isNotEmpty)
                IconButton(icon: const Icon(Icons.call), onPressed: () => launchUrl(Uri.parse('tel:${shop.phone}'))),
              IconButton(icon: const Icon(Icons.directions), onPressed: () => openDirections(shop.latitude, shop.longitude)),
            ]),
          ),
          if (shop.ratingCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [Stars(shop.rating), Text('  ${shop.rating.toStringAsFixed(1)} (${shop.ratingCount} रिव्यू)')]),
            ),
          const SectionTitle('अभी की डील'),
          AsyncView(
            value: ref.watch(shopDealsProvider(id)),
            data: (deals) => deals.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('अभी कोई लाइव डील नहीं।'))
                : Column(children: [for (final d in deals) DealCard(deal: d, onTap: () => context.push('/deal/${d.id}'))]),
          ),
          const SectionTitle('रिव्यू'),
          AsyncView(
            value: ref.watch(shopReviewsProvider(id)),
            data: (reviews) => reviews.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('अभी कोई रिव्यू नहीं।'))
                : Column(children: [
                    for (final r in reviews)
                      ListTile(
                        leading: Stars(r.rating, size: 14),
                        title: Text(r.comment.isEmpty ? '—' : r.comment),
                        subtitle: Text('${r.customerName} · ${dateTime(r.createdAt)}${r.reply.isEmpty ? '' : '\nदुकान: ${r.reply}'}'),
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
      appBar: AppBar(title: const Text('पसंदीदा दुकानें')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(favoritesProvider.future),
        child: AsyncView(
          value: ref.watch(favoritesProvider),
          onRetry: () => ref.invalidate(favoritesProvider),
          data: (shops) => shops.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  EmptyView(icon: Icons.favorite_border, message: 'दुकान पेज पर ♥ दबाएं — उनकी नई डील की सूचना सबसे पहले मिलेगी'),
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
