from decimal import Decimal

from rest_framework import serializers

from apps.products.models import Product

from .models import Inventory, InventoryMovement

QUANTITY = {"max_digits": 10, "decimal_places": 2}


class InventorySerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source="product.name", read_only=True)
    unit = serializers.CharField(source="product.unit", read_only=True)
    is_low = serializers.BooleanField(read_only=True)

    class Meta:
        model = Inventory
        fields = ["id", "product", "product_name", "unit", "quantity_on_hand", "low_stock_threshold", "is_low", "updated_at"]


class AdjustSerializer(serializers.Serializer):
    product = serializers.PrimaryKeyRelatedField(queryset=Product.objects.all())
    change = serializers.DecimalField(**QUANTITY)
    reason = serializers.ChoiceField(choices=[c for c in InventoryMovement.Reason.choices if c[0] != "sale"])
    note = serializers.CharField(required=False, allow_blank=True, max_length=255)
    low_stock_threshold = serializers.DecimalField(**QUANTITY, min_value=Decimal("0"), required=False)

    def validate_product(self, product):
        if product.shop.merchant.user_id != self.context["request"].user.id:
            raise serializers.ValidationError("Product not found.")
        return product


class MovementSerializer(serializers.ModelSerializer):
    class Meta:
        model = InventoryMovement
        fields = ["id", "change", "balance_after", "reason", "reference", "note", "created_at"]
