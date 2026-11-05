import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/i18n/i18n.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/deal_card.dart';
import '../customer_providers.dart';

/// Nearby shops on an OpenStreetMap map; shops with live deals show their best discount.
class ShopsMapScreen extends ConsumerStatefulWidget {
  const ShopsMapScreen({super.key});

  @override
  ConsumerState<ShopsMapScreen> createState() => _ShopsMapScreenState();
}

class _ShopsMapScreenState extends ConsumerState<ShopsMapScreen> {
  ShopSummary? _selected;

  @override
  Widget build(BuildContext context) {
    final here = ref.watch(locationProvider).value;
    final shops = ref.watch(nearbyShopsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('नक्शे पर दुकानें'))),
      body: here == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: ll.LatLng(here.latitude, here.longitude),
                  initialZoom: 14,
                  onTap: (_, _) => setState(() => _selected = null),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.microbargain.micro_bargain',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: ll.LatLng(here.latitude, here.longitude),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
                        ),
                      ),
                    ),
                    for (final s in shops.value ?? <ShopSummary>[])
                      Marker(
                        point: ll.LatLng(s.latitude, s.longitude),
                        width: 74,
                        height: 52,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(onTap: () => setState(() => _selected = s), child: _Pin(shop: s, selected: _selected?.id == s.id)),
                      ),
                  ]),
                  const SimpleAttributionWidget(source: Text('OpenStreetMap')),
                ],
              ),
              if (shops.isLoading) const LinearProgressIndicator(),
              if (_selected != null)
                Positioned(left: 16, right: 16, bottom: 24, child: _ShopPreview(shop: _selected!)),
            ]),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.shop, required this.selected});

  final ShopSummary shop;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final live = shop.liveDealsCount > 0;
    final color = live ? AppTheme.accent : AppTheme.muted;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedScale(
        scale: selected ? 1.15 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
          ),
          child: live && shop.maxDiscount != null
              ? Text('${shop.maxDiscount!.round()}% OFF', style: TextStyle(color: AppTheme.onAccent, fontWeight: FontWeight.w800, fontSize: 12))
              : const Icon(Icons.storefront_rounded, color: Colors.white, size: 16),
        ),
      ),
      Icon(Icons.arrow_drop_down_rounded, color: color, size: 22),
    ]);
  }
}

class _ShopPreview extends StatelessWidget {
  const _ShopPreview({required this.shop});

  final ShopSummary shop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          shop.liveDealsCount > 0 ? tr('{0} लाइव डील · {1}', [shop.liveDealsCount, shop.address]) : shop.address,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: FilledButton(onPressed: () => context.push('/shop/${shop.id}'), child: Text(tr('देखें'))),
        leading: shop.rating > 0 ? Stars(shop.rating.round(), size: 12) : null,
      ),
    );
  }
}
