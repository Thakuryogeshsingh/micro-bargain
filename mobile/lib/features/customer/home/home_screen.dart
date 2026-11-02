import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../notifications/notifications_screen.dart';
import '../cart/cart.dart';
import '../customer_providers.dart';

const _sorts = {
  'distance': 'सबसे पास',
  'discount': 'सबसे ज़्यादा छूट',
  'price': 'सबसे सस्ता',
  'ending_soon': 'जल्द खत्म',
  'newest': 'नई डील',
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(dealFiltersProvider);
    final location = ref.watch(locationProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('पास की डील'),
          Text(
            location.value?.isFallback == true ? '📍 भरतपुर (लोकेशन बंद है)' : '📍 आपके आस-पास ${distance(filters.radius)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'लोकेशन ताज़ा करें',
            onPressed: () => ref.invalidate(locationProvider),
            icon: const Icon(Icons.my_location),
          ),
          const NotificationBell(),
        ],
      ),
      floatingActionButton: cart.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/cart'),
              icon: const Icon(Icons.shopping_cart),
              label: Text('कार्ट (${cart.length}) · ${rupees(cart.fold<double>(0, (s, l) => s + l.total))}'),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(locationProvider);
          ref.invalidate(bannersProvider);
          await ref.read(nearbyDealsProvider.future);
        },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _SearchBar(initial: filters.query)),
          const SliverToBoxAdapter(child: _Banners()),
          const SliverToBoxAdapter(child: _CategoryChips()),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (final r in AppConfig.searchRadiiMeters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(distance(r)),
                      selected: filters.radius == r,
                      onSelected: (_) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(radius: r)),
                    ),
                  ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  initialValue: filters.sort,
                  onSelected: (s) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(sort: s)),
                  itemBuilder: (_) => [for (final e in _sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
                  child: Chip(avatar: const Icon(Icons.sort, size: 18), label: Text(_sorts[filters.sort]!)),
                ),
              ]),
            ),
          ),
          ref.watch(nearbyDealsProvider).when(
                loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
                error: (e, _) => SliverFillRemaining(
                  child: ErrorView(message: e.toString(), onRetry: () => ref.invalidate(nearbyDealsProvider)),
                ),
                data: (deals) => deals.isEmpty
                    ? const SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyView(
                          icon: Icons.local_offer_outlined,
                          message: 'अभी इस दायरे में कोई डील नहीं।\nदायरा बढ़ाकर देखें या थोड़ी देर बाद आएं।',
                        ),
                      )
                    : SliverList.builder(
                        itemCount: deals.length,
                        itemBuilder: (_, i) => DealCard(deal: deals[i], onTap: () => context.push('/deal/${deals[i].id}')),
                      ),
              ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ]),
      ),
    );
  }
}

class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar({required this.initial});

  final String initial;

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  late final _controller = TextEditingController(text: widget.initial);

  void _search(String value) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(query: value.trim()));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: _search,
        decoration: InputDecoration(
          hintText: 'सब्ज़ी, फल, दूध, दुकान खोजें…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _controller.clear();
              _search('');
            },
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(dealFiltersProvider).category;
    final categories = ref.watch(categoriesProvider).value ?? [];
    void select(int? id) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(category: () => id));
    return SizedBox(
      height: 48,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(label: const Text('सभी'), selected: selected == null, onSelected: (_) => select(null)),
        ),
        for (final c in categories)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text('${c.icon} ${c.nameHi}'.trim()),
              selected: selected == c.id,
              onSelected: (_) => select(selected == c.id ? null : c.id),
            ),
          ),
      ]),
    );
  }
}

class _Banners extends ConsumerWidget {
  const _Banners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(bannersProvider).value ?? [];
    if (banners.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 140,
      child: PageView(
        controller: PageController(viewportFraction: 0.92),
        children: [
          for (final b in banners)
            GestureDetector(
              onTap: () {
                ref.read(apiProvider).post('/advertisements/${b['id']}/click/');
                context.push('/shop/${b['shop_id']}');
              },
              child: Card(
                child: Stack(fit: StackFit.expand, children: [
                  if (b['banner_image'] != null) CachedNetworkImage(imageUrl: b['banner_image'], fit: BoxFit.cover),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: double.infinity,
                      color: Colors.black45,
                      padding: const EdgeInsets.all(8),
                      child: Text('${b['title']} · ${b['shop_name']}', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
