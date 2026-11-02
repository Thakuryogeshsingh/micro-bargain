import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../models/models.dart';
import 'common.dart';

class DealImage extends StatelessWidget {
  const DealImage(this.url, {super.key, this.size = 88});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.shopping_basket_outlined),
    );
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
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
      Text('${rupees(offer)}/${unitLabel(unit)}',
          style: (large ? style.headlineSmall : style.titleMedium)
              ?.copyWith(color: AppTheme.deal, fontWeight: FontWeight.bold)),
      Text(rupees(normal), style: style.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough)),
    ]);
  }
}

class DealCard extends StatelessWidget {
  const DealCard({super.key, required this.deal, required this.onTap});

  final Deal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: deal.isFeatured
          ? RoundedRectangleBorder(
              side: const BorderSide(color: AppTheme.featured, width: 1.5), borderRadius: BorderRadius.circular(12))
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(children: [
                DealImage(deal.image),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    color: AppTheme.deal,
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    child: Text('${deal.discountPercent.round()}% OFF',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (deal.isFeatured)
                  const Text('⭐ फीचर्ड', style: TextStyle(fontSize: 11, color: Colors.brown)),
                Text(deal.productName, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                PriceLine(offer: deal.offerPrice, normal: deal.normalPrice, unit: deal.unit),
                const SizedBox(height: 4),
                Text(
                  '${deal.shop.name} · ${distance(deal.distanceM)}${deal.shop.ratingCount > 0 ? ' · ★${deal.shop.rating.toStringAsFixed(1)}' : ''}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Ticker(
                  builder: (_) => Text(
                    '⏱ ${timeLeft(deal.expiresAt)} · ${qty(deal.quantityAvailable)} ${unitLabel(deal.unit)} बचा',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Small stars row for ratings.
class Stars extends StatelessWidget {
  const Stars(this.rating, {super.key, this.size = 16});

  final num rating;
  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating.round() ? Icons.star : Icons.star_border, size: size, color: Colors.amber.shade700),
      ]);
}
