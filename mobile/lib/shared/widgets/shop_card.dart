import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../models/models.dart';
import 'motion.dart';
import 'visuals.dart';

const _categoryArt = {
  'Fruits': '🍎🍌🍇',
  'Vegetables': '🥬🍅🥕',
  'Grocery': '🌾🍚🫘',
  'Dairy Products': '🥛🧀🧈',
  'Bakery': '🍞🥐🍪',
  'Snacks': '🥨🍿🥜',
  'Beverages': '🥤🧃🍵',
  'Meat and Seafood': '🍗🐟🥚',
  'Household Essentials': '🧴🧽🧻',
};

/// Green "4.3 ★" badge used on shop cards.
class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key, this.count = 0});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final fresh = count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: fresh ? AppTheme.chip : const Color(0xFF15803D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        fresh ? tr('नई') : '${rating.toStringAsFixed(1)} ★',
        style: TextStyle(color: fresh ? AppTheme.ink : Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

/// Big restaurant-style card for a shop.
class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shop, required this.onTap, this.onFavorite, this.index = 0});

  final ShopSummary shop;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final int index;

  @override
  Widget build(BuildContext context) {
    final (_, pastel) = productLook(shop.name, shop.categoryName);
    final art = _categoryArt[shop.categoryName] ?? '🛍️🧺🏪';
    return FadeSlideIn(
      index: index,
      child: Pressable(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(24), boxShadow: AppTheme.softShadow(0.08)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 160,
              child: Stack(fit: StackFit.expand, children: [
                Hero(
                  tag: 'shop-cover-${shop.id}',
                  child: shop.coverImage != null
                      ? CachedNetworkImage(imageUrl: shop.coverImage!, fit: BoxFit.cover)
                      : Container(
                          color: pastel,
                          alignment: Alignment.center,
                          child: Text(art, style: const TextStyle(fontSize: 54, letterSpacing: 6)),
                        ),
                ),
                if (shop.maxDiscount != null && shop.maxDiscount! > 0)
                  Positioned(
                    left: 0,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
                      decoration: const BoxDecoration(
                        gradient: AppTheme.dealGradient,
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
                      ),
                      child: Text(tr('{0}% तक छूट', [shop.maxDiscount!.round()]),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                  ),
                if (onFavorite != null)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Pressable(
                      onTap: onFavorite,
                      child: CircleAvatar(
                        radius: 17,
                        backgroundColor: Colors.white,
                        child: Icon(shop.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 19, color: shop.isFavorite ? const Color(0xFFE11D48) : Colors.black54),
                      ),
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.bolt_rounded, size: 15, color: Color(0xFFF59E0B)),
                      Text(tr('{0} मिनट', [shop.prepMinutes]),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black87)),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(shop.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.ink)),
                  ),
                  const SizedBox(width: 8),
                  RatingBadge(shop.rating, count: shop.ratingCount),
                ]),
                const SizedBox(height: 4),
                Text(
                  [shop.categoryName, if (shop.distanceM != null) distance(shop.distanceM), shop.address].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.muted),
                ),
                if (shop.liveDealsCount > 0) ...[
                  const SizedBox(height: 8),
                  Divider(color: AppTheme.muted.withValues(alpha: 0.15)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Text('🔥', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(tr('{0} डील लाइव', [shop.liveDealsCount]),
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary)),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
