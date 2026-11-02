import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../shared/models/models.dart';

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/merchants/dashboard/'));
});

/// The merchant's shop (one per merchant in the pilot), or null before it is created.
final myShopProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final shops = await ref.watch(apiProvider).list('/merchants/shop/list/');
  return shops.isEmpty ? null : Map<String, dynamic>.from(shops.first);
});

final merchantProductsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  return [for (final p in await ref.watch(apiProvider).list('/products/', query: {'page_size': 100})) Product.fromJson(p)];
});

final merchantDealsProvider = FutureProvider.autoDispose<List<Deal>>((ref) async {
  return [for (final d in await ref.watch(apiProvider).list('/deals/', query: {'page_size': 100})) Deal.fromJson(d)];
});

final merchantReservationsProvider = FutureProvider.autoDispose<List<Reservation>>((ref) async {
  return [for (final r in await ref.watch(apiProvider).list('/reservations/')) Reservation.fromJson(r)];
});

final merchantOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  return [for (final o in await ref.watch(apiProvider).list('/orders/')) Order.fromJson(o)];
});

final inventoryProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return (await ref.watch(apiProvider).list('/inventory/')).cast<Map<String, dynamic>>();
});

final plansProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return (await ref.watch(apiProvider).get('/subscriptions/plans/') as List).cast<Map<String, dynamic>>();
});

final currentPlanProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/subscriptions/current/'));
});

final adsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return (await ref.watch(apiProvider).list('/advertisements/')).cast<Map<String, dynamic>>();
});

final merchantReviewsProvider = FutureProvider.autoDispose<List<Review>>((ref) async {
  return [for (final r in await ref.watch(apiProvider).list('/reviews/')) Review.fromJson(r)];
});

final commissionSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/commissions/summary/'));
});

final salesProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, days) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/analytics/merchant-sales/', query: {'days': days}));
});
