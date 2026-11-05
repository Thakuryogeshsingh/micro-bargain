import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../models/models.dart';
import 'common.dart';
import 'motion.dart';

/// Product photo, or a soft gradient tile with a basket when there is none.
class DealImage extends StatelessWidget {
  const DealImage(this.url, {super.key, this.size = 88});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFE8F7EC), Color(0xFFFFF1E4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Icon(Icons.shopping_basket_rounded, color: AppTheme.primary.withValues(alpha: 0.45), size: size.isFinite ? size * 0.4 : 64),
    );
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
        child: Text('/${unitLabel(unit)}', style: style.bodyMedium?.copyWith(color: Colors.black54)),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(rupees(normal),
            style: style.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough, color: Colors.black38)),
      ),
    ]);
  }
}

/// "⏱ 1 घं 20 मि बाकी" chip; turns red in the last hour.
class CountdownChip extends StatelessWidget {
  const CountdownChip(this.until, {super.key});

  final DateTime until;

  @override
  Widget build(BuildContext context) {
    return Ticker(builder: (_) {
      final urgent = until.difference(DateTime.now()) < const Duration(hours: 1);
      final color = urgent ? const Color(0xFFDC2626) : AppTheme.primaryDark;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Text(timeLeft(until), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
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
            color: Colors.white,
            borderRadius: AppTheme.radius,
            boxShadow: AppTheme.softShadow(0.06),
            border: deal.isFeatured ? Border.all(color: AppTheme.featured, width: 1.6) : null,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              Hero(
                tag: 'deal-image-${deal.id}',
                child: ClipRRect(borderRadius: BorderRadius.circular(14), child: DealImage(deal.image, size: 104)),
              ),
              Positioned(left: 6, top: 6, child: DiscountBadge(deal.discountPercent)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (deal.isFeatured)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(tr('⭐ फीचर्ड'),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                  ),
                Text(deal.productName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                PriceLine(offer: deal.offerPrice, normal: deal.normalPrice, unit: deal.unit),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.storefront_rounded, size: 14, color: Colors.black45),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        deal.shop.name,
                        if (deal.distanceM != null) distance(deal.distanceM),
                        if (deal.shop.ratingCount > 0) '★ ${deal.shop.rating.toStringAsFixed(1)}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
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
        decoration: BoxDecoration(color: const Color(0xFFF1F5F2), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
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
