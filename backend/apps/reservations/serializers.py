from decimal import Decimal

from rest_framework import serializers

from .models import DealReservation


class ReservationCreateSerializer(serializers.Serializer):
    deal = serializers.IntegerField()
    quantity = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=Decimal("0.01"))
    pickup_at = serializers.DateTimeField(required=False, help_text="When the customer will come; empty = within 45 minutes")


class ReasonSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, max_length=255)


class PickupSerializer(serializers.Serializer):
    pickup_code = serializers.RegexField(r"^\d{4}$", error_messages={"invalid": "Enter the 4-digit pickup code."})


class ReservationSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source="deal.product.name", read_only=True)
    shop_name = serializers.CharField(source="shop.name", read_only=True)
    shop_address = serializers.CharField(source="shop.address_line", read_only=True)
    shop_phone = serializers.CharField(source="shop.phone", read_only=True)
    shop_latitude = serializers.FloatField(source="shop.latitude", read_only=True)
    shop_longitude = serializers.FloatField(source="shop.longitude", read_only=True)
    savings = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model = DealReservation
        fields = [
            "id", "reservation_number", "status", "deal", "product_name",
            "shop", "shop_name", "shop_phone", "shop_address", "shop_latitude", "shop_longitude",
            "quantity", "unit", "unit_price", "total_amount", "savings", "pickup_code",
            "pickup_at", "expires_at", "confirmed_at", "completed_at", "closed_reason", "created_at",
        ]


class MerchantReservationSerializer(ReservationSerializer):
    """The shop sees a masked customer number and never the pickup code (the customer tells it at pickup)."""

    customer_phone = serializers.SerializerMethodField()
    customer_name = serializers.CharField(source="customer.name", read_only=True)

    class Meta(ReservationSerializer.Meta):
        fields = [f for f in ReservationSerializer.Meta.fields if f != "pickup_code"] + ["customer_name", "customer_phone"]

    def get_customer_phone(self, obj) -> str:
        return obj.customer.phone[:5] + "xxxxx"
