import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../../shared/widgets/motion.dart';
import '../../notifications/notifications_screen.dart';
import '../cart/cart.dart';
import '../offers/offers.dart';
import '../customer_providers.dart';

// i18n:off (translated where used)
const _sorts = {
  'distance': 'सबसे पास',
  'discount': 'सबसे ज़्यादा छूट',
  'price': 'सबसे सस्ता',
  'ending_soon': 'जल्द खत्म',
  'newest': 'नई डील',
};
// i18n:on

/// Emoji for each category, keyed by the Hindi name the server sends.
const _categoryEmoji = {
  'फल': '🍎',
  'सब्ज़ी': '🥬',
  'किराना': '🛒',
  'डेयरी': '🥛',
  'बेकरी': '🍞',
  'नमकीन-स्नैक्स': '🥨',
  'पेय': '🥤',
  'मीट और सीफ़ूड': '🍗',
  'घरेलू सामान': '🧴',
  'अन्य लोकल सामान': '🛍️',
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final cartTotal = cart.fold<double>(0, (s, l) => s + l.total);

    return Scaffold(
      floatingActionButton: AnimatedScale(
        scale: cart.isEmpty ? 0 : 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppTheme.dealGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: AppTheme.deal.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: FloatingActionButton.extended(
            heroTag: 'cart-fab',
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            onPressed: () => context.push('/cart'),
            icon: const Icon(Icons.shopping_bag_rounded),
            label: Text(tr('कार्ट ({0}) · {1}', [cart.length, rupees(cartTotal)]),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      body: RefreshIndicator(
        edgeOffset: 120,
        onRefresh: () async {
          ref.invalidate(locationProvider);
          ref.invalidate(bannersProvider);
          await ref.read(nearbyDealsProvider.future);
        },
        child: CustomScrollView(slivers: [
          const _Header(),
          const SliverToBoxAdapter(child: _Banners()),
          const SliverToBoxAdapter(child: OffersStrip()),
          const SliverToBoxAdapter(child: _CategoryStrip()),
          const SliverToBoxAdapter(child: _FilterRow()),
          ref.watch(nearbyDealsProvider).when(
                loading: () => const SliverToBoxAdapter(child: DealListSkeleton()),
                error: (e, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorView(message: e.toString(), onRetry: () => ref.invalidate(nearbyDealsProvider)),
                ),
                data: (deals) => deals.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: FadeSlideIn(
                          child: EmptyView(
                            icon: Icons.local_offer_outlined,
                            message: tr('अभी इस दायरे में कोई डील नहीं।\nदायरा बढ़ाकर देखें या थोड़ी देर बाद आएं।'),
                          ),
                        ),
                      )
                    : SliverList.builder(
                        itemCount: deals.length,
                        itemBuilder: (_, i) => DealCard(
                          deal: deals[i],
                          index: i,
                          onTap: () => context.push('/deal/${deals[i].id}'),
                        ),
                      ),
              ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ]),
      ),
    );
  }
}

/// Green gradient header: greeting, location, bell and search. Collapses to a slim bar on scroll.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    final filters = ref.watch(dealFiltersProvider);
    final location = ref.watch(locationProvider);
    const white = Colors.white;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 178,
      backgroundColor: AppTheme.primaryDark,
      foregroundColor: white,
      title: Text(tr('पास की डील'), style: const TextStyle(color: white, fontWeight: FontWeight.w700)),
      actions: [
        IconButton(
          tooltip: tr('लोकेशन ताज़ा करें'),
          onPressed: () => ref.invalidate(locationProvider),
          icon: const Icon(Icons.my_location_rounded, color: white),
        ),
        const IconTheme(data: IconThemeData(color: white), child: NotificationBell()),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Container(
          decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${tr('नमस्ते, {0}', [user?.name.split(' ').first ?? ''])} 👋',
                  style: const TextStyle(color: white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  location.value?.isFallback == true
                      ? tr('📍 भरतपुर (लोकेशन बंद है)')
                      : tr('📍 आपके आस-पास {0}', [distance(filters.radius)]),
                  style: TextStyle(color: white.withValues(alpha: 0.85), fontSize: 13),
                ),
              ]),
            ),
          ),
        ),
      ),
      bottom: PreferredSize(preferredSize: const Size.fromHeight(64), child: _SearchBar(initial: filters.query)),
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow(0.12)),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: tr('सब्ज़ी, फल, दूध, दुकान खोजें…'),
            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary),
            isDense: true,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _controller.clear();
                _search('');
                FocusScope.of(context).unfocus();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Round emoji tiles for categories; the selected one is highlighted with a green ring.
class _CategoryStrip extends ConsumerWidget {
  const _CategoryStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(dealFiltersProvider).category;
    final categories = ref.watch(categoriesProvider).value ?? [];
    void select(int? id) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(category: () => id));
    final tiles = [
      (id: null as int?, emoji: '✨', label: tr('सभी')),
      for (final c in categories) (id: c.id as int?, emoji: _categoryEmoji[c.nameHi] ?? '🛍️', label: c.label),
    ];
    return SizedBox(
      height: 104,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
        itemCount: tiles.length,
        itemBuilder: (context, i) {
          final tile = tiles[i];
          final active = selected == tile.id;
          return FadeSlideIn(
            index: i,
            offset: 0.3,
            child: Pressable(
              onTap: () => select(active && tile.id != null ? null : tile.id),
              child: SizedBox(
                width: 74,
                child: Column(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppTheme.primary.withValues(alpha: 0.14) : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: active ? AppTheme.primary : Colors.transparent, width: 2),
                      boxShadow: AppTheme.softShadow(active ? 0.0 : 0.06),
                    ),
                    child: Text(tile.emoji, style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tile.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? AppTheme.primaryDark : Colors.black87,
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterRow extends ConsumerWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(dealFiltersProvider);
    final count = ref.watch(nearbyDealsProvider).value?.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(tr('पास की डील'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: count == null
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey(count),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(gradient: AppTheme.dealGradient, borderRadius: BorderRadius.circular(12)),
                    child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: filters.sort,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (s) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(sort: s)),
            itemBuilder: (_) => [for (final e in _sorts.entries) PopupMenuItem(value: e.key, child: Text(tr(e.value)))],
            child: Chip(avatar: const Icon(Icons.tune_rounded, size: 18), label: Text(tr(_sorts[filters.sort]!))),
          ),
        ]),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final r in AppConfig.searchRadiiMeters)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(distance(r)),
                  selected: filters.radius == r,
                  showCheckmark: false,
                  avatar: filters.radius == r ? const Icon(Icons.near_me_rounded, size: 16) : null,
                  onSelected: (_) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(radius: r)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Banners extends ConsumerStatefulWidget {
  const _Banners();

  @override
  ConsumerState<_Banners> createState() => _BannersState();
}

class _BannersState extends ConsumerState<_Banners> {
  final _controller = PageController(viewportFraction: 0.9);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(bannersProvider).value ?? [];
    if (banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _controller,
            itemCount: banners.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final b = banners[i];
              return Pressable(
                onTap: () {
                  ref.read(apiProvider).post('/advertisements/${b['id']}/click/');
                  context.push('/shop/${b['shop_id']}');
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(borderRadius: AppTheme.radius, boxShadow: AppTheme.softShadow()),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    if (b['banner_image'] != null)
                      CachedNetworkImage(imageUrl: b['banner_image'], fit: BoxFit.cover)
                    else
                      const DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.heroGradient)),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.transparent, Colors.black54], begin: Alignment.center, end: Alignment.bottomCenter),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Text('${b['title']} · ${b['shop_name']}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < banners.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _page ? AppTheme.primary : Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
      ]),
    );
  }
}
