import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/location/location_service.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/models.dart';

class DealFilters {
  const DealFilters({this.radius = AppConfig.defaultSearchRadiusMeters, this.category, this.sort = 'distance', this.query = ''});

  final int radius;
  final int? category;
  final String sort; // distance | price | discount | ending_soon | newest
  final String query;

  DealFilters copyWith({int? radius, int? Function()? category, String? sort, String? query}) => DealFilters(
        radius: radius ?? this.radius,
        category: category != null ? category() : this.category,
        sort: sort ?? this.sort,
        query: query ?? this.query,
      );
}

class DealFiltersController extends Notifier<DealFilters> {
  @override
  DealFilters build() => const DealFilters();

  void update(DealFilters Function(DealFilters) change) => state = change(state);
}

final dealFiltersProvider = NotifierProvider<DealFiltersController, DealFilters>(DealFiltersController.new);

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final data = await ref.watch(apiProvider).get('/categories/') as List;
  return [for (final c in data) Category.fromJson(c)];
});

final nearbyDealsProvider = FutureProvider.autoDispose<List<Deal>>((ref) async {
  final here = await ref.watch(locationProvider.future);
  final filters = ref.watch(dealFiltersProvider);
  final results = await ref.watch(apiProvider).list('/deals/nearby/', query: {
    'latitude': here.latitude.toStringAsFixed(6),
    'longitude': here.longitude.toStringAsFixed(6),
    'radius': filters.radius,
    'category': filters.category,
    'sort': filters.sort,
    'q': filters.query,
  });
  return [for (final d in results) Deal.fromJson(d)];
});

final bannersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final here = await ref.watch(locationProvider.future);
  final data = await ref.watch(apiProvider).get('/advertisements/banners/',
      query: {'latitude': here.latitude, 'longitude': here.longitude}) as List;
  return data.cast<Map<String, dynamic>>();
});

final dealProvider = FutureProvider.autoDispose.family<Deal, int>((ref, id) async {
  return Deal.fromJson(await ref.watch(apiProvider).get('/deals/$id/'));
});

final shopProvider = FutureProvider.autoDispose.family<ShopSummary, int>((ref, id) async {
  return ShopSummary.fromJson(await ref.watch(apiProvider).get('/shops/$id/'));
});

final shopDealsProvider = FutureProvider.autoDispose.family<List<Deal>, int>((ref, id) async {
  return [for (final d in await ref.watch(apiProvider).list('/deals/shop/$id/')) Deal.fromJson(d)];
});

final shopReviewsProvider = FutureProvider.autoDispose.family<List<Review>, int>((ref, id) async {
  return [for (final r in await ref.watch(apiProvider).list('/reviews/shop/$id/')) Review.fromJson(r)];
});

final myReservationsProvider = FutureProvider.autoDispose<List<Reservation>>((ref) async {
  return [for (final r in await ref.watch(apiProvider).list('/reservations/')) Reservation.fromJson(r)];
});

final myOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  return [for (final o in await ref.watch(apiProvider).list('/orders/')) Order.fromJson(o)];
});

final reservationProvider = FutureProvider.autoDispose.family<Reservation, int>((ref, id) async {
  return Reservation.fromJson(await ref.watch(apiProvider).get('/reservations/$id/'));
});

final orderProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) async {
  return Order.fromJson(await ref.watch(apiProvider).get('/orders/$id/'));
});

final favoritesProvider = FutureProvider.autoDispose<List<ShopSummary>>((ref) async {
  return [for (final s in await ref.watch(apiProvider).list('/shops/favorites/')) ShopSummary.fromJson(s)];
});

final addressesProvider = FutureProvider.autoDispose<List<Address>>((ref) async {
  final data = await ref.watch(apiProvider).get('/customers/addresses/') as List;
  return [for (final a in data) Address.fromJson(a)];
});

final customerProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/customers/profile/'));
});
