import '../../core/i18n/i18n.dart';

// Typed views of the API's JSON. Money and quantities arrive as strings ("60.00") and are parsed to double
// for display only; anything sent back to the server is sent as a string again.

double _d(Object? value) => value == null ? 0 : double.tryParse(value.toString()) ?? 0;
DateTime? _t(Object? value) => value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

class Category {
  Category({required this.id, required this.name, required this.nameHi, required this.icon});

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(id: j['id'], name: j['name'], nameHi: j['name_hi'] ?? j['name'], icon: j['icon'] ?? '');

  final int id;
  final String name;
  final String nameHi;
  final String icon;

  /// Category names come from the server in Hindi; other languages translate them in the catalogue.
  String get label => tr(nameHi);
}

class ShopSummary {
  ShopSummary({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.ratingCount,
    this.phone = '',
    this.distanceM,
    this.isFavorite = false,
    this.categoryName = '',
    this.offersDelivery = false,
    this.coverImage,
  });

  factory ShopSummary.fromJson(Map<String, dynamic> j) => ShopSummary(
        id: j['id'],
        name: j['name'],
        address: [j['address_line'], j['landmark'], j['city']].where((s) => s != null && s != '').join(', '),
        latitude: _d(j['latitude']),
        longitude: _d(j['longitude']),
        rating: _d(j['rating_avg']),
        ratingCount: j['rating_count'] ?? 0,
        phone: j['phone'] ?? '',
        distanceM: j['distance_m'],
        isFavorite: j['is_favorite'] ?? false,
        categoryName: j['category_name'] ?? '',
        offersDelivery: j['offers_delivery'] ?? false,
        coverImage: j['cover_image'],
      );

  final int id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double rating;
  final int ratingCount;
  final String phone;
  final int? distanceM;
  final bool isFavorite;
  final String categoryName;
  final bool offersDelivery;
  final String? coverImage;
}

class Deal {
  Deal({
    required this.id,
    required this.shop,
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.description,
    required this.image,
    required this.unit,
    required this.normalPrice,
    required this.offerPrice,
    required this.discountPercent,
    required this.quantityAvailable,
    required this.expiresAt,
    required this.fulfilment,
    required this.status,
    this.distanceM,
    this.isFeatured = false,
    this.quantityTotal,
    this.quantityReserved,
    this.quantitySold,
  });

  factory Deal.fromJson(Map<String, dynamic> j) => Deal(
        id: j['id'],
        shop: ShopSummary.fromJson(j['shop']),
        productId: j['product_id'],
        productName: j['product_name'],
        categoryName: j['category_name'] ?? '',
        description: j['description'] ?? '',
        image: j['image'],
        unit: j['unit'],
        normalPrice: _d(j['normal_price']),
        offerPrice: _d(j['offer_price']),
        discountPercent: _d(j['discount_percent']),
        quantityAvailable: _d(j['quantity_available']),
        expiresAt: _t(j['expires_at'])!,
        fulfilment: j['fulfilment'],
        status: j['status'],
        distanceM: j['distance_m'],
        isFeatured: j['is_featured'] ?? false,
        quantityTotal: j.containsKey('quantity_total') ? _d(j['quantity_total']) : null,
        quantityReserved: j.containsKey('quantity_reserved') ? _d(j['quantity_reserved']) : null,
        quantitySold: j.containsKey('quantity_sold') ? _d(j['quantity_sold']) : null,
      );

  final int id;
  final ShopSummary shop;
  final int productId;
  final String productName;
  final String categoryName;
  final String description;
  final String? image;
  final String unit;
  final double normalPrice;
  final double offerPrice;
  final double discountPercent;
  final double quantityAvailable;
  final DateTime expiresAt;
  final String fulfilment; // pickup | delivery | both
  final String status;
  final int? distanceM;
  final bool isFeatured;
  // Merchant view only.
  final double? quantityTotal;
  final double? quantityReserved;
  final double? quantitySold;

  bool get canPickup => fulfilment != 'delivery';
  bool get canDeliver => fulfilment != 'pickup';
  bool get isLive => status == 'active' && expiresAt.isAfter(DateTime.now()) && quantityAvailable > 0;
}

class Reservation {
  Reservation({
    required this.id,
    required this.number,
    required this.status,
    required this.dealId,
    required this.productName,
    required this.shopId,
    required this.shopName,
    required this.shopAddress,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.total,
    required this.savings,
    required this.expiresAt,
    required this.createdAt,
    this.pickupCode,
    this.pickupAt,
    this.closedReason = '',
    this.customerName = '',
    this.customerPhone = '',
  });

  factory Reservation.fromJson(Map<String, dynamic> j) => Reservation(
        id: j['id'],
        number: j['reservation_number'],
        status: j['status'],
        dealId: j['deal'],
        productName: j['product_name'],
        shopId: j['shop'],
        shopName: j['shop_name'],
        shopAddress: j['shop_address'] ?? '',
        shopLatitude: _d(j['shop_latitude']),
        shopLongitude: _d(j['shop_longitude']),
        quantity: _d(j['quantity']),
        unit: j['unit'],
        unitPrice: _d(j['unit_price']),
        total: _d(j['total_amount']),
        savings: _d(j['savings']),
        expiresAt: _t(j['expires_at'])!,
        createdAt: _t(j['created_at'])!,
        pickupCode: j['pickup_code'],
        pickupAt: _t(j['pickup_at']),
        closedReason: j['closed_reason'] ?? '',
        customerName: j['customer_name'] ?? '',
        customerPhone: j['customer_phone'] ?? '',
      );

  final int id;
  final String number;
  final String status;
  final int dealId;
  final String productName;
  final int shopId;
  final String shopName;
  final String shopAddress;
  final double shopLatitude;
  final double shopLongitude;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double total;
  final double savings;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String? pickupCode; // customer only
  final DateTime? pickupAt; // chosen pickup time, if any
  final String closedReason;
  final String customerName; // merchant only
  final String customerPhone; // merchant only

  bool get isOpen => status == 'pending' || status == 'confirmed';
}

class OrderItem {
  OrderItem({required this.productName, required this.quantity, required this.unit, required this.unitPrice, required this.lineTotal});

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        productName: j['product_name'],
        quantity: _d(j['quantity']),
        unit: j['unit'],
        unitPrice: _d(j['unit_price']),
        lineTotal: _d(j['line_total']),
      );

  final String productName;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double lineTotal;
}

class Order {
  Order({
    required this.id,
    required this.number,
    required this.status,
    required this.fulfilment,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.shopId,
    required this.shopName,
    required this.shopPhone,
    required this.items,
    required this.subtotal,
    required this.savings,
    required this.couponDiscount,
    required this.deliveryFee,
    required this.total,
    required this.refunded,
    required this.deliveryAddress,
    required this.createdAt,
    this.pickupCode,
    this.expiresAt,
    this.cancelReason = '',
    this.customerName = '',
    this.customerPhone = '',
  });

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'],
        number: j['order_number'],
        status: j['status'],
        fulfilment: j['fulfilment'],
        paymentMethod: j['payment_method'],
        paymentStatus: j['payment_status'],
        shopId: j['shop'],
        shopName: j['shop_name'],
        shopPhone: j['shop_phone'] ?? '',
        items: (j['items'] as List).map((i) => OrderItem.fromJson(i)).toList(),
        subtotal: _d(j['subtotal']),
        savings: _d(j['savings']),
        couponDiscount: _d(j['coupon_discount']),
        deliveryFee: _d(j['delivery_fee']),
        total: _d(j['total_amount']),
        refunded: _d(j['refunded_amount']),
        deliveryAddress: j['delivery_address'] ?? '',
        createdAt: _t(j['created_at'])!,
        pickupCode: j['pickup_code'],
        expiresAt: _t(j['expires_at']),
        cancelReason: j['cancel_reason'] ?? '',
        customerName: j['customer_name'] ?? '',
        customerPhone: j['customer_phone'] ?? '',
      );

  final int id;
  final String number;
  final String status;
  final String fulfilment;
  final String paymentMethod;
  final String paymentStatus;
  final int shopId;
  final String shopName;
  final String shopPhone;
  final List<OrderItem> items;
  final double subtotal;
  final double savings;
  final double couponDiscount;
  final double deliveryFee;
  final double total;
  final double refunded;
  final String deliveryAddress;
  final DateTime createdAt;
  final String? pickupCode;
  final DateTime? expiresAt;
  final String cancelReason;
  final String customerName;
  final String customerPhone;

  bool get isDelivery => fulfilment == 'delivery';
}

class Product {
  Product({
    required this.id,
    required this.shopId,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.unit,
    required this.standardPrice,
    required this.isActive,
    required this.images,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'],
        shopId: j['shop'],
        categoryId: j['category'],
        name: j['name'],
        description: j['description'] ?? '',
        unit: j['unit'],
        standardPrice: _d(j['standard_price']),
        isActive: j['is_active'] ?? true,
        images: [for (final i in (j['images'] as List? ?? [])) i['image'] as String],
      );

  final int id;
  final int shopId;
  final int categoryId;
  final String name;
  final String description;
  final String unit;
  final double standardPrice;
  final bool isActive;
  final List<String> images;
}

class Address {
  Address({
    required this.id,
    required this.label,
    required this.line,
    required this.city,
    required this.pincode,
    required this.isDefault,
  });

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: j['id'],
        label: j['label'],
        line: [j['address_line'], j['landmark']].where((s) => s != null && s != '').join(', '),
        city: j['city'],
        pincode: j['pincode'],
        isDefault: j['is_default'] ?? false,
      );

  final int id;
  final String label;
  final String line;
  final String city;
  final String pincode;
  final bool isDefault;
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'],
        kind: j['kind'],
        title: j['title'],
        body: j['body'],
        data: Map<String, dynamic>.from(j['data'] ?? {}),
        isRead: j['is_read'],
        createdAt: _t(j['created_at'])!,
      );

  final int id;
  final String kind;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;
}

class Review {
  Review({required this.id, required this.customerName, required this.rating, required this.comment, required this.reply, required this.createdAt});

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: j['id'],
        customerName: j['customer_name'],
        rating: j['rating'],
        comment: j['comment'] ?? '',
        reply: j['merchant_reply'] ?? '',
        createdAt: _t(j['created_at'])!,
      );

  final int id;
  final String customerName;
  final int rating;
  final String comment;
  final String reply;
  final DateTime createdAt;
}

double parseNum(Object? value) => _d(value);
DateTime? parseTime(Object? value) => _t(value);
