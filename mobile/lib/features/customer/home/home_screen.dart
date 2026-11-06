import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../../shared/widgets/location_picker.dart';
import '../../../shared/widgets/motion.dart';
import '../../notifications/notifications_screen.dart';
import '../cart/cart.dart';
import '../cart/cart_bar.dart';
import '../customer_providers.dart';
import '../deals/collection_screen.dart';
import '../growth/growth_screens.dart';
import '../offers/offers.dart';
import '../../../shared/widgets/shop_card.dart';
import '../../../shared/widgets/visuals.dart';
import '../../../shared/widgets/voice.dart';

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

/// Adds one unit of a deal to the cart (asking first if the cart holds another shop's items).
Future<void> quickAdd(BuildContext context, WidgetRef ref, Deal deal) async {
  HapticFeedback.lightImpact();
  final cart = ref.read(cartProvider.notifier);
  final step = (deal.unit == 'kg' || deal.unit == 'litre') ? 0.5 : 1.0;
  final existing = ref.read(cartProvider).where((l) => l.deal.id == deal.id).firstOrNull;
  final quantity = (existing?.quantity ?? 0) + step;
  if (quantity > deal.quantityAvailable) {
    showMessage(context, tr('बस इतना ही स्टॉक बचा है'));
    return;
  }
  if (!cart.add(deal, quantity)) {
    final replace = await confirm(context, tr('कार्ट में दूसरी दुकान का सामान है'),
        message: tr('एक ऑर्डर में एक ही दुकान का सामान आ सकता है। पुराना कार्ट हटा कर यह डालें?'), ok: tr('हाँ, बदलें'), icon: Icons.shopping_bag_outlined);
    if (!replace) return;
    cart.replaceWith(deal, step);
  }
  if (context.mounted) showMessage(context, '${deal.productName} · ${tr('कार्ट में जोड़ा गया')}');
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteShops = {for (final s in ref.watch(favoritesProvider).value ?? <ShopSummary>[]) s.id};

    Future<void> toggleFavorite(int shopId, bool isFav) async {
      final api = ref.read(apiProvider);
      HapticFeedback.lightImpact();
      final ok = await runAction(context, () async {
        isFav ? await api.delete('/shops/$shopId/favorite/') : await api.post('/shops/$shopId/favorite/');
      }, success: isFav ? tr('पसंदीदा से हटाया') : tr('पसंदीदा में जोड़ा — नई डील पर सूचना मिलेगी'));
      if (ok) {
        ref.invalidate(favoritesProvider);
        ref.invalidate(nearbyShopsProvider);
      }
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(locationProvider);
          ref.invalidate(bannersProvider);
          ref.invalidate(offersProvider(null));
          ref.invalidate(collectionDealsProvider('sort=discount'));
          await ref.read(nearbyShopsProvider.future);
        },
        child: CustomScrollView(slivers: [
          const SliverToBoxAdapter(child: _Header()),
          const SliverToBoxAdapter(child: CampaignBanner()),
          const SliverToBoxAdapter(child: _OfferBanners()),
          const SliverToBoxAdapter(child: _Banners()),
          SliverToBoxAdapter(child: _SectionTitle(tr('कैटेगरी'))),
          const SliverToBoxAdapter(child: _CategoryPills()),
          SliverToBoxAdapter(child: _SectionTitle(tr('आपके लिए खास'))),
          const SliverToBoxAdapter(child: CollectionTiles()),
          const SliverToBoxAdapter(child: GroupDealsStrip()),
          const SliverToBoxAdapter(child: _TopDeals()),
          const SliverToBoxAdapter(child: _Leaderboard()),
          const SliverToBoxAdapter(child: _FilterRow()),
          ref.watch(nearbyShopsProvider).when(
                loading: () => const SliverToBoxAdapter(child: DealListSkeleton(count: 3)),
                error: (e, _) => SliverToBoxAdapter(
                  child: ErrorView(message: e.toString(), onRetry: () => ref.invalidate(nearbyShopsProvider)),
                ),
                data: (shops) => shops.isEmpty
                    ? SliverToBoxAdapter(
                        child: FadeSlideIn(
                          child: EmptyView(
                            icon: Icons.storefront_outlined,
                            message: tr('अभी इस दायरे में कोई डील नहीं।\nदायरा बढ़ाकर देखें या थोड़ी देर बाद आएं।'),
                          ),
                        ),
                      )
                    : SliverList.builder(
                        itemCount: shops.length,
                        itemBuilder: (_, i) => ShopCard(
                          shop: shops[i],
                          index: i,
                          onFavorite: () => toggleFavorite(shops[i].id, favoriteShops.contains(shops[i].id)),
                          onTap: () => context.push('/shop/${shops[i].id}'),
                        ),
                      ),
              ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 12, 8),
        child: Row(children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink)),
          ),
          ?trailing,
        ]),
      );
}

/// Rounded dark header: location, bell and search.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    final filters = ref.watch(dealFiltersProvider);
    final location = ref.watch(locationProvider);
    final minimal = AppTheme.minimal;
    final fg = minimal ? AppTheme.ink : Colors.white;
    final bubble = minimal ? AppTheme.chip : Colors.white.withValues(alpha: 0.15);
    return Container(
      decoration: minimal
          ? BoxDecoration(color: AppTheme.background)
          : BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32))),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Pressable(
                onTap: () => chooseBrowsePlace(context, ref),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: bubble, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.location_on_rounded, color: minimal ? AppTheme.primary : Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('नमस्ते, {0}', [user?.name.split(' ').first ?? '']),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg.withValues(alpha: minimal ? 0.55 : 0.85), fontSize: 13)),
                  Text(
                    location.value?.label != null
                        ? '${location.value!.label} ▾'
                        : location.value?.isFallback == true
                            ? plain(tr('📍 भरतपुर (लोकेशन बंद है)'))
                            : plain(tr('📍 आपके आस-पास {0}', [distance(filters.radius)])),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ]),
              ),
              Container(
                decoration: BoxDecoration(color: bubble, borderRadius: BorderRadius.circular(14)),
                child: IconTheme(data: IconThemeData(color: fg), child: const NotificationBell()),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: bubble, borderRadius: BorderRadius.circular(14)),
                child: CartIconButton(color: fg),
              ),
            ]),
            if (minimal) ...[
              const SizedBox(height: 18),
              Text(tr('सबसे सस्ता,\nसबसे पास।'),
                  style: TextStyle(fontSize: 32, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -1.2, color: AppTheme.ink)),
            ],
            const SizedBox(height: 18),
            _SearchBar(initial: filters.query),
          ]),
        ),
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
    final sort = ref.watch(dealFiltersProvider).sort;
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) context.push('/search', extra: value.trim());
          },
          decoration: InputDecoration(
            hintText: tr('सब्ज़ी, फल, दूध, दुकान खोजें…'),
            filled: true,
            fillColor: AppTheme.minimal ? AppTheme.chip : null,
            prefixIcon: Icon(Icons.search_rounded, color: AppTheme.muted),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: tr('बोलकर खोजें'),
                icon: Icon(Icons.mic_rounded, color: AppTheme.accentInk),
                onPressed: () async {
                  final text = await listenOnce(context, hint: tr('जैसे: "टमाटर" या "दूध"'));
                  if (text == null || !mounted) return;
                  if (context.mounted) context.push('/search', extra: text);
                },
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _controller.clear();
                  _search('');
                  FocusScope.of(context).unfocus();
                },
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 10),
      PopupMenuButton<String>(
        initialValue: sort,
        tooltip: tr(_sorts[sort]!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (s) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(sort: s)),
        itemBuilder: (_) => [for (final e in _sorts.entries) PopupMenuItem(value: e.key, child: Text(tr(e.value)))],
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(16)),
          child: Icon(Icons.tune_rounded, color: AppTheme.onAccent),
        ),
      ),
    ]);
  }
}

/// Big swipeable offer banners (coupons); tapping copies the code.
class _OfferBanners extends ConsumerStatefulWidget {
  const _OfferBanners();

  @override
  ConsumerState<_OfferBanners> createState() => _OfferBannersState();
}

class _OfferBannersState extends ConsumerState<_OfferBanners> {
  final _controller = PageController(viewportFraction: 0.9);
  int _page = 0;

  static const _gradients = [
    [Color(0xFFFF7A59), Color(0xFFFFB443)],
    [Color(0xFF7C3AED), Color(0xFFDB2777)],
    [Color(0xFF0EA5E9), Color(0xFF22C55E)],
    [Color(0xFFF43F5E), Color(0xFFF59E0B)],
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offers = ref.watch(offersProvider(null)).value ?? [];
    if (offers.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      _SectionTitle(tr('खास ऑफ़र')),
      SizedBox(
        height: 150,
        child: PageView.builder(
          controller: _controller,
          itemCount: offers.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, i) {
            final o = offers[i];
            return Pressable(
              onTap: () {
                Clipboard.setData(ClipboardData(text: o['code']));
                showMessage(context, tr('कूपन {0} कॉपी हुआ — कार्ट में लगाएं', [o['code']]));
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                decoration: BoxDecoration(
                  gradient: AppTheme.minimal ? AppTheme.heroGradient : LinearGradient(colors: _gradients[i % _gradients.length]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppTheme.softShadow(0.12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(tr('खास ऑफ़र'), style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
                      Text(offerTitle(o),
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                      const SizedBox(height: 4),
                      Text(offerCondition(o),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: AppTheme.minimal ? AppTheme.accent : Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Text(o['code'],
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: AppTheme.minimal ? Colors.black : _gradients[i % _gradients.length][0])),
                      ),
                    ]),
                  ),
                  Icon(Icons.local_offer_rounded, size: 52, color: AppTheme.minimal ? AppTheme.accent : Colors.white.withValues(alpha: 0.85)),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      _Dots(count: offers.length, index: _page),
    ]);
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? AppTheme.primary : AppTheme.muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]);
}

/// Category pills with a round photo; the selected one is filled with the theme colour.
class _CategoryPills extends ConsumerWidget {
  const _CategoryPills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(dealFiltersProvider).category;
    final categories = ref.watch(categoriesProvider).value ?? [];
    void select(int? id) => ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(category: () => id));
    final tiles = [
      (id: null as int?, photo: '', label: tr('सभी')),
      for (final c in categories) (id: c.id as int?, photo: c.icon, label: c.label),
    ];
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tile = tiles[i];
          final active = selected == tile.id;
          return FadeSlideIn(
            index: i,
            offset: 0.3,
            child: Pressable(
              onTap: () => select(active && tile.id != null ? null : tile.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
                decoration: BoxDecoration(
                  color: active ? AppTheme.primaryDark : AppTheme.card,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: AppTheme.softShadow(active ? 0.15 : 0.05),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: active ? Colors.white.withValues(alpha: 0.18) : AppTheme.chip,
                    backgroundImage: tile.photo.isEmpty ? null : CachedNetworkImageProvider(tile.photo),
                    child: tile.photo.isEmpty
                        ? Icon(Icons.apps_rounded, size: 20, color: active ? Colors.white : AppTheme.primaryDark)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(tile.label,
                      style: TextStyle(fontWeight: FontWeight.w700, color: active ? Colors.white : AppTheme.ink)),
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
    final count = ref.watch(nearbyShopsProvider).value?.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(
        tr('पास की दुकानें'),
        trailing: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: count == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(count),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(12)),
                  child: Text('$count', style: TextStyle(color: AppTheme.onAccent, fontWeight: FontWeight.w800)),
                ),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(Icons.map_rounded, size: 18, color: AppTheme.accentInk),
              label: Text(tr('नक्शा')),
              onPressed: () => context.push('/map'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(Icons.checklist_rounded, size: 18, color: AppTheme.accentInk),
              label: Text(tr('शॉपिंग लिस्ट')),
              onPressed: () => context.push('/shopping-list'),
            ),
          ),
          for (final r in AppConfig.searchRadiiMeters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
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
    ]);
  }
}

/// Paid shop banners (promotions) near the customer.
class _Banners extends ConsumerStatefulWidget {
  const _Banners();

  @override
  ConsumerState<_Banners> createState() => _BannersState();
}

class _BannersState extends ConsumerState<_Banners> {
  final _controller = PageController(viewportFraction: 0.9);

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
      child: SizedBox(
        height: 150,
        child: PageView.builder(
          controller: _controller,
          itemCount: banners.length,
          itemBuilder: (context, i) {
            final b = banners[i];
            return Pressable(
              onTap: () {
                ref.read(apiProvider).post('/advertisements/${b['id']}/click/');
                context.push('/shop/${b['shop_id']}');
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: AppTheme.softShadow()),
                clipBehavior: Clip.antiAlias,
                child: Stack(fit: StackFit.expand, children: [
                  if (b['banner_image'] != null)
                    CachedNetworkImage(imageUrl: b['banner_image'], fit: BoxFit.cover)
                  else
                    DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.heroGradient)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.transparent, Colors.black54], begin: Alignment.center, end: Alignment.bottomCenter),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Text('${b['title']} · ${b['shop_name']}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}


/// Horizontal row of the biggest discounts nearby, Blinkit-style.
class _TopDeals extends ConsumerWidget {
  const _TopDeals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(collectionDealsProvider('sort=discount')).value ?? [];
    if (deals.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      _SectionTitle(
        tr('आज की टॉप डील्स'),
        trailing: TextButton(
          onPressed: () => context.push('/collection', extra: {'title': tr('सबसे बड़ी छूट'), 'query': 'sort=discount'}),
          child: Text(tr('सभी देखें')),
        ),
      ),
      SizedBox(
        height: 262,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: deals.length.clamp(0, 10),
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(
            width: 168,
            child: DealGridCard(
              deal: deals[i],
              index: i,
              onAdd: () => quickAdd(context, ref, deals[i]),
              onTap: () => context.push('/deal/${deals[i].id}'),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Mohalla ranking: shops that saved their customers the most this week.
class _Leaderboard extends ConsumerWidget {
  const _Leaderboard();

  static const _medalColors = [Color(0xFFF5B301), Color(0xFF9CA3AF), Color(0xFFB45309)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(leaderboardProvider).value ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(tr('इस हफ़्ते के टॉप दुकानदार')),
      SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final row = rows[i];
            final shop = row['shop'] as Map;
            final rank = row['rank'] as int;
            return FadeSlideIn(
              index: i,
              child: Pressable(
                onTap: () => context.push('/shop/${shop['id']}'),
                child: Container(
                  width: 190,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: rank == 1 ? const Color(0xFFF5B301) : AppTheme.chip),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: rank <= 3 ? _medalColors[rank - 1] : AppTheme.chip,
                        child: Text('$rank',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: rank <= 3 ? Colors.white : AppTheme.ink)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(shop['name'], maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
                      ),
                    ]),
                    const Spacer(),
                    Text(tr('{0} बचत कराई', [rupees(parseNum(row['savings']))]),
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF15803D))),
                    Text(tr('{0} खरीदारी', [row['purchases']]), style: TextStyle(fontSize: 12, color: AppTheme.muted)),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Browse near where I am, or anywhere else (another city, e.g. to order for family there).
Future<void> chooseBrowsePlace(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.my_location_rounded),
          title: Text(tr('मेरी अभी की लोकेशन')),
          onTap: () => Navigator.pop(sheet, 'gps'),
        ),
        ListTile(
          leading: const Icon(Icons.map_rounded),
          title: Text(tr('मैप पर जगह / दूसरा शहर चुनें')),
          subtitle: Text(tr('किसी और के लिए वहाँ की दुकान से ऑर्डर करें')),
          onTap: () => Navigator.pop(sheet, 'map'),
        ),
      ]),
    ),
  );
  if (choice == 'gps') {
    chooseBrowseLocation(ref, null);
  } else if (choice == 'map' && context.mounted) {
    final here = ref.read(locationProvider).value;
    final place = await pickLocationOnMap(context, latitude: here?.latitude, longitude: here?.longitude, title: tr('कहाँ की दुकानें देखें?'));
    if (place == null) return;
    chooseBrowseLocation(
      ref,
      LatLng(place.latitude, place.longitude, label: place.city.isEmpty ? tr('चुनी हुई जगह') : place.city),
    );
  }
}
