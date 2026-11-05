from decimal import Decimal

from rest_framework import serializers

from .models import Coupon, Order, OrderItem


class OrderLineInputSerializer(serializers.Serializer):
    deal = serializers.IntegerField()
    quantity = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=Decimal("0.01"))


class OrderCreateSerializer(serializers.Serializer):
    items = OrderLineInputSerializer(many=True)
    fulfilment = serializers.ChoiceField(choices=Order.Fulfilment.choices, default=Order.Fulfilment.PICKUP)
    payment_method = serializers.ChoiceField(choices=Order.PaymentMethod.choices)
    address = serializers.IntegerField(required=False, help_text="Address id; required for delivery")
    coupon_code = serializers.CharField(required=False, allow_blank=True, max_length=20)
    note = serializers.CharField(required=False, allow_blank=True, max_length=255)


class OfferSerializer(serializers.ModelSerializer):
    shop_name = serializers.CharField(source="shop.name", default=None, read_only=True)
    is_personal = serializers.SerializerMethodField()

    class Meta:
        model = Coupon
        fields = ["code", "description", "discount_type", "value", "max_discount", "min_order_amount", "valid_until",
                  "shop", "shop_name", "first_order_only", "is_personal"]

    def get_is_personal(self, obj) -> bool:
        return obj.customer_id is not None


class CouponCheckSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=20)
    shop = serializers.IntegerField()
    subtotal = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=Decimal("0"))


class OrderItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderItem
        fields = ["id", "deal", "product_name", "unit", "quantity", "unit_price", "normal_unit_price", "line_total"]


class OrderSerializer(serializers.ModelSerializer):
    items = OrderItemSerializer(many=True, read_only=True)
    shop_name = serializers.CharField(source="shop.name", read_only=True)
    shop_phone = serializers.CharField(source="shop.phone", read_only=True)
    shop_latitude = serializers.FloatField(source="shop.latitude", read_only=True)
    shop_longitude = serializers.FloatField(source="shop.longitude", read_only=True)
    coupon_code = serializers.CharField(source="coupon.code", read_only=True, default=None)

    class Meta:
        model = Order
        fields = [
            "id", "order_number", "status", "fulfilment", "payment_method", "payment_status",
            "shop", "shop_name", "shop_phone", "shop_latitude", "shop_longitude", "items",
            "subtotal", "savings", "coupon_code", "coupon_discount", "plus_discount", "delivery_fee", "total_amount", "refunded_amount",
            "delivery_address", "delivery_latitude", "delivery_longitude", "pickup_code", "note",
            "expires_at", "confirmed_at", "ready_at", "completed_at", "cancelled_at", "cancel_reason", "created_at",
        ]


class MerchantOrderSerializer(OrderSerializer):
    """The shop gets a masked phone and never the pickup code (the customer tells it at handover)."""

    customer_name = serializers.CharField(source="customer.name", read_only=True)
    customer_phone = serializers.SerializerMethodField()

    class Meta(OrderSerializer.Meta):
        fields = [f for f in OrderSerializer.Meta.fields if f != "pickup_code"] + ["customer_name", "customer_phone"]

    def get_customer_phone(self, obj) -> str:
        # Delivery needs a reachable number once the shop has committed to the order.
        if obj.fulfilment == Order.Fulfilment.DELIVERY and obj.status in (Order.Status.CONFIRMED, Order.Status.OUT_FOR_DELIVERY):
            return obj.customer.phone
        return obj.customer.phone[:5] + "xxxxx"
