import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../models/models.dart';
import 'common.dart';
import 'motion.dart';
import 'visuals.dart';

/// Product photo, or the product's emoji on a pastel tile when there is none.
class DealImage extends StatelessWidget {
  const DealImage(this.url, {super.key, this.size = 88, this.name = '', this.category = ''});

  final String? url;
  final double size;
  final String name;
  final String category;

  @override
  Widget build(BuildContext context) {
    final placeholder = ProductArt(name: name, category: category, size: size);
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

/// Orange gradient "40% OFF" pill.
class DiscountBadge extends StatelessWidget {
  const DiscountBadge(this.percent, {super.key, this.large = false});

  final double percent;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
      decoration: BoxDecoration(
        gradient: AppTheme.dealGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppTheme.deal.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Text(
        '${percent.round()}% OFF',
        style: TextStyle(color: Colors.white, fontSize: large ? 15 : 11, fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
    );
  }
}

class PriceLine extends StatelessWidget {
  const PriceLine({super.key, required this.offer, required this.normal, required this.unit, this.large = false});

  final double offer;
  final double normal;
  final String unit;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
      Text(rupees(offer),
          style: (large ? style.headlineMedium : style.titleLarge)
              ?.copyWith(color: AppTheme.deal, fontWeight: FontWeight.w800, height: 1.1)),
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('/${unitLabel(unit)}', style: style.bodyMedium?.copyWith(color: AppTheme.muted)),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(rupees(normal),
            style: style.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough, color: AppTheme.muted)),
      ),
    ]);
  }
}

/// "⏱ 1 घं 20 मि बाकी" chip; turns red in the last hour.
class CountdownChip extends StatelessWidget {
  const CountdownChip(this.until, {super.key, this.compact = false});

  final DateTime until;

  /// Small solid version that sits on top of a product image.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Ticker(builder: (_) {
      final urgent = until.difference(DateTime.now()) < const Duration(hours: 1);
      final color = urgent ? const Color(0xFFDC2626) : (AppTheme.dark ? AppTheme.primary : AppTheme.primaryDark);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 3 : 4),
        decoration: BoxDecoration(
          color: compact ? AppTheme.card.withValues(alpha: 0.92) : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_outlined, size: compact ? 12 : 14, color: color),
          const SizedBox(width: 3),
          Text(timeLeft(until), style: TextStyle(fontSize: compact ? 10 : 12, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
    });
  }
}

class DealCard extends StatelessWidget {
  const DealCard({super.key, required this.deal, required this.onTap, this.index = 0});

  final Deal deal;
  final VoidCallback onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeSlideIn(
      index: index,
      child: Pressable(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: AppTheme.radius,
            boxShadow: AppTheme.softShadow(0.06),
            border: deal.isFeatured ? Border.all(color: AppTheme.featured, width: 1.6) : null,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              Hero(
                tag: 'deal-image-${deal.id}',
                child: ClipRRect(borderRadius: BorderRadius.circular(14), child: DealImage(deal.image, size: 104, name: deal.productName, category: deal.categoryName)),
              ),
              Positioned(left: 6, top: 6, child: DiscountBadge(deal.discountPercent)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (deal.isHappyHour)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(plain(tr('🌙 हैप्पी आवर')),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF7C3AED))),
                  ),
                if (deal.isFeatured)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(plain(tr('⭐ फीचर्ड')),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                  ),
                Text(deal.productName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                PriceLine(offer: deal.offerPrice, normal: deal.normalPrice, unit: deal.unit),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.storefront_rounded, size: 14, color: AppTheme.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        deal.shop.name,
                        if (deal.distanceM != null) distance(deal.distanceM),
                        if (deal.shop.ratingCount > 0) '★ ${deal.shop.rating.toStringAsFixed(1)}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  CountdownChip(deal.expiresAt),
                  _Pill(
                    icon: Icons.inventory_2_outlined,
                    text: '${qty(deal.quantityAvailable)} ${unitLabel(deal.unit)}',
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppTheme.chip, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppTheme.muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink)),
        ]),
      );
}

/// Small stars row for ratings.
class Stars extends StatelessWidget {
  const Stars(this.rating, {super.key, this.size = 16});

  final num rating;
  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating.round() ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: Colors.amber.shade700),
      ]);
}

/// Grid tile for the home screen: big pastel image, heart, discount, price and a round "+" to add to cart.
class DealGridCard extends StatelessWidget {
  const DealGridCard({
    super.key,
    required this.deal,
    required this.onTap,
    required this.onAdd,
    this.onFavorite,
    this.favorite = false,
    this.index = 0,
  });

  final Deal deal;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback? onFavorite;
  final bool favorite;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeSlideIn(
      index: index,
      child: Pressable(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(color: AppTheme.card, borderRadius: AppTheme.radius, boxShadow: AppTheme.softShadow(0.06)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Hero(
                      tag: 'deal-image-${deal.id}',
                      child: DealImage(deal.image, size: double.infinity, name: deal.productName, category: deal.categoryName),
                    ),
                  ),
                ),
                Positioned(left: 12, top: 12, child: DiscountBadge(deal.discountPercent)),
                if (deal.isHappyHour)
                  Positioned(
                    left: 12,
                    top: 38,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(20)),
                      child: Text(plain(tr('🌙 हैप्पी आवर')),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
                if (onFavorite != null)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Pressable(
                      onTap: onFavorite,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                        child: CircleAvatar(
                          key: ValueKey(favorite),
                          radius: 15,
                          backgroundColor: AppTheme.card,
                          child: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 18, color: favorite ? const Color(0xFFE11D48) : AppTheme.muted),
                        ),
                      ),
                    ),
                  ),
                Positioned(left: 12, bottom: 12, child: CountdownChip(deal.expiresAt, compact: true)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(deal.productName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink)),
                Text(
                  [deal.shop.name, if (deal.distanceM != null) distance(deal.distanceM)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                ),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(rupees(deal.normalPrice),
                          style: TextStyle(fontSize: 11, color: AppTheme.muted, decoration: TextDecoration.lineThrough)),
                      Text('${rupees(deal.offerPrice)}/${unitLabel(deal.unit)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                    ]),
                  ),
                  Pressable(
                    onTap: onAdd,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: AppTheme.primaryDark, shape: BoxShape.circle),
                      child: const Icon(Icons.add_rounded, color: Colors.white),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
