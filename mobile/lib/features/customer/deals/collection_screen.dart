import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../../shared/widgets/motion.dart';
import '../cart/cart_bar.dart';
import '../customer_providers.dart';
import '../home/home_screen.dart';

/// A themed list of deals, e.g. "under ₹50" or "biggest discounts".
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.title, required this.query});

  final String title;
  final String query; // e.g. "sort=discount&max_price=50"

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(collectionDealsProvider(query));
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [CartIconButton()]),
      bottomNavigationBar: const SafeArea(child: CartBar()),
      body: deals.when(
        loading: () => const SingleChildScrollView(child: DealListSkeleton()),
        error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(collectionDealsProvider(query))),
        data: (list) => list.isEmpty
            ? EmptyView(icon: Icons.local_offer_outlined, message: tr('अभी इस दायरे में कोई डील नहीं।\nदायरा बढ़ाकर देखें या थोड़ी देर बाद आएं।'))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.66,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => DealGridCard(
                  deal: list[i],
                  index: i,
                  onAdd: () => quickAdd(context, ref, list[i]),
                  onTap: () => context.push('/deal/${list[i].id}'),
                ),
              ),
      ),
    );
  }
}

/// The collections offered on the home screen.
List<(IconData icon, String title, String query, List<Color> colors)> homeCollections() => [
      (Icons.currency_rupee_rounded, tr('₹50 से कम'), 'max_price=50&sort=price', const [Color(0xFF22C55E), Color(0xFF15803D)]),
      (Icons.local_fire_department_rounded, tr('सबसे बड़ी छूट'), 'sort=discount', const [Color(0xFFFF7A59), Color(0xFFE11D48)]),
      (Icons.timer_outlined, tr('जल्द खत्म'), 'sort=ending_soon', const [Color(0xFFF59E0B), Color(0xFFEA580C)]),
      (Icons.fiber_new_rounded, tr('नई डील'), 'sort=newest', const [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
    ];

class CollectionTiles extends StatelessWidget {
  const CollectionTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final collections = homeCollections();
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: collections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (icon, title, query, colors) = collections[i];
          return FadeSlideIn(
            index: i,
            offset: 0.3,
            child: Pressable(
              onTap: () => context.push('/collection', extra: {'title': title, 'query': query}),
              child: Container(
                width: 120,
                padding: const EdgeInsets.all(12),
                decoration: AppTheme.minimal
                    ? BoxDecoration(color: AppTheme.chip, borderRadius: BorderRadius.circular(20))
                    : BoxDecoration(
                        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(20),
                      ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  AppTheme.minimal
                      ? CircleAvatar(radius: 18, backgroundColor: AppTheme.accent, child: Icon(icon, size: 20, color: Colors.black))
                      : Icon(icon, size: 30, color: Colors.white),
                  Text(title,
                      maxLines: 2,
                      style: TextStyle(
                          color: AppTheme.minimal ? AppTheme.ink : Colors.white, fontWeight: FontWeight.w900, fontSize: 14, height: 1.15)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
