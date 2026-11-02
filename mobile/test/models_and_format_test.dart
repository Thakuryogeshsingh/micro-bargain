import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_bargain/core/network/api_client.dart';
import 'package:micro_bargain/core/utils/format.dart';
import 'package:micro_bargain/shared/models/models.dart';
import 'package:micro_bargain/shared/widgets/deal_card.dart';

// Shape copied from the backend's DealSerializer (GET /deals/nearby/).
Map<String, dynamic> dealJson({bool featured = false}) => {
      'id': 7,
      'shop': {
        'id': 3,
        'name': 'Gupta Fruits',
        'address_line': 'Mandi Road',
        'city': 'Bharatpur',
        'latitude': 27.2152,
        'longitude': 77.489,
        'rating_avg': '4.50',
        'rating_count': 2,
      },
      'product_id': 11,
      'product_name': 'सेब (शिमला)',
      'category': 1,
      'category_name': 'Fruits',
      'description': '',
      'image': null,
      'unit': 'kg',
      'normal_price': '100.00',
      'offer_price': '60.00',
      'discount_percent': '40.00',
      'quantity_available': '18.50',
      'starts_at': '2026-11-02T10:00:00+05:30',
      'expires_at': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      'seconds_left': 7200,
      'fulfilment': 'both',
      'status': 'active',
      'published_at': '2026-11-02T10:00:00+05:30',
      'distance_m': 850,
      'is_featured': featured,
    };

void main() {
  group('format', () {
    test('rupees', () {
      expect(rupees(60), '₹60');
      expect(rupees(62.5), '₹62.50');
      expect(rupees(125000), '₹1,25,000');
    });

    test('qty drops trailing zeros', () {
      expect(qty(2), '2');
      expect(qty(1.5), '1.5');
      expect(qty(18.25), '18.25');
    });

    test('distance', () {
      expect(distance(850), '850 मी.');
      expect(distance(2400), '2.4 कि.मी.');
      expect(distance(null), '');
    });
  });

  group('models', () {
    test('deal parses API json', () {
      final deal = Deal.fromJson(dealJson());
      expect(deal.offerPrice, 60);
      expect(deal.quantityAvailable, 18.5);
      expect(deal.shop.rating, 4.5);
      expect(deal.canPickup && deal.canDeliver, isTrue);
      expect(deal.isLive, isTrue);
      expect(deal.quantityTotal, isNull); // customer view has no stock breakdown
    });

    test('api error shows first field error', () {
      final error = ApiException('Validation failed.', code: 'validation_error', details: {
        'phone': ['Enter a valid 10-digit mobile number.'],
      });
      expect(error.friendly, 'Enter a valid 10-digit mobile number.');
    });
  });

  testWidgets('deal card shows price, discount and featured badge', (tester) async {
    final deal = Deal.fromJson(dealJson(featured: true));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DealCard(deal: deal, onTap: () {}))));
    expect(find.text('सेब (शिमला)'), findsOneWidget);
    expect(find.text('40% OFF'), findsOneWidget);
    expect(find.text('₹60/किलो'), findsOneWidget);
    expect(find.textContaining('फीचर्ड'), findsOneWidget);
  });
}
