import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../../shared/widgets/motion.dart';
import '../cart/cart_bar.dart';
import '../growth/growth_screens.dart';
import '../home/home_screen.dart';

/// Search results across all nearby shops, cheapest first (key: the search text).
final searchProvider = FutureProvider.autoDispose.family<List<Deal>, String>((ref, q) async {
  final here = await ref.watch(locationProvider.future);
  final rows = await ref.watch(apiProvider).list('/deals/nearby/', query: {
    'latitude': here.latitude.toStringAsFixed(6),
    'longitude': here.longitude.toStringAsFixed(6),
    'radius': 10000,
    'q': q,
    'sort': 'price',
    'page_size': 50,
  });
  return [for (final r in rows) Deal.fromJson(r)];
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initial = ''});

  final String initial;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initial);
  late String _query = widget.initial.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const SafeArea(child: CartBar()),
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: widget.initial.isEmpty,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            hintText: tr('सब्ज़ी, फल, दूध, दुकान खोजें…'),
            filled: true,
            fillColor: AppTheme.chip,
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          IconButton(
            tooltip: tr('दाम गिरने पर बताएं'),
            onPressed: () => addPriceAlert(context, ref, query: _query),
            icon: const Icon(Icons.add_alert_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _query.isEmpty
          ? EmptyView(icon: Icons.search_rounded, message: tr('जैसे: paneer, टमाटर, doodh, bread'))
          : AsyncView(
              value: ref.watch(searchProvider(_query)),
              onRetry: () => ref.invalidate(searchProvider(_query)),
              data: (deals) => deals.isEmpty
                  ? EmptyView(icon: Icons.search_off_rounded, message: tr('"{0}" की कोई डील पास में नहीं मिली', [_query]))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: deals.length + 1,
                      itemBuilder: (_, i) => i == 0
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(tr('{0} दुकानों में · सबसे सस्ता पहले', [deals.map((d) => d.shop.id).toSet().length]),
                                  style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w600)),
                            )
                          : FadeSlideIn(index: i - 1, child: _ResultTile(deal: deals[i - 1], cheapest: i == 1)),
                    ),
            ),
    );
  }
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({required this.deal, required this.cheapest});

  final Deal deal;
  final bool cheapest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Pressable(
      onTap: () => context.push('/deal/${deal.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppTheme.softShadow(0.05),
          border: cheapest ? Border.all(color: AppTheme.minimal ? AppTheme.accent : AppTheme.primary, width: 2) : null,
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: DealImage(deal.image, size: 72, name: deal.productName, category: deal.categoryName),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (cheapest)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.minimal ? AppTheme.accent : AppTheme.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text(tr('सबसे सस्ता'),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppTheme.minimal ? Colors.black : Colors.white)),
                ),
              Text(deal.productName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
              Text([deal.shop.name, if (deal.distanceM != null) distance(deal.distanceM)].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppTheme.muted)),
              const SizedBox(height: 4),
              Row(children: [
                Text('${rupees(deal.offerPrice)}/${unitLabel(deal.unit)}',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.ink)),
                const SizedBox(width: 6),
                Text(rupees(deal.normalPrice),
                    style: TextStyle(fontSize: 12, color: AppTheme.muted, decoration: TextDecoration.lineThrough)),
              ]),
            ]),
          ),
          AddStepper(deal: deal, onAdd: () => quickAdd(context, ref, deal)),
        ]),
      ),
    );
  }
}
