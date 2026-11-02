import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';

class CartLine {
  const CartLine(this.deal, this.quantity);

  final Deal deal;
  final double quantity;

  double get total => deal.offerPrice * quantity;
  double get savings => (deal.normalPrice - deal.offerPrice) * quantity;
}

/// One order = one shop, so the cart only holds deals from a single shop.
class CartController extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => const [];

  ShopSummary? get shop => state.isEmpty ? null : state.first.deal.shop;

  /// Returns false if the deal is from a different shop than what is already in the cart.
  bool add(Deal deal, double quantity) {
    if (state.isNotEmpty && state.first.deal.shop.id != deal.shop.id) return false;
    state = [
      for (final line in state)
        if (line.deal.id != deal.id) line,
      CartLine(deal, quantity),
    ];
    return true;
  }

  void replaceWith(Deal deal, double quantity) => state = [CartLine(deal, quantity)];

  void remove(int dealId) => state = [for (final l in state) if (l.deal.id != dealId) l];

  void clear() => state = const [];
}

final cartProvider = NotifierProvider<CartController, List<CartLine>>(CartController.new);
