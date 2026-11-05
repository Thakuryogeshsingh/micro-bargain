from rest_framework import serializers

from apps.categories.models import Category
from common.validators import validate_coordinates

from .models import Address, CustomerProfile


class CustomerProfileSerializer(serializers.ModelSerializer):
    preferred_categories = serializers.PrimaryKeyRelatedField(
        many=True, queryset=Category.objects.filter(is_active=True), required=False
    )

    class Meta:
        model = CustomerProfile
        fields = [
            "search_radius_m",
            "notify_nearby_deals",
            "notify_favorite_shops",
            "notify_order_updates",
            "preferred_categories",
        ]


class AddressSerializer(serializers.ModelSerializer):
    class Meta:
        model = Address
        fields = [
            "id", "label", "address_line", "landmark", "city", "state", "pincode",
            "latitude", "longitude", "is_default", "contact_name", "contact_phone", "created_at",
        ]
        read_only_fields = ["id", "created_at"]

    def validate(self, attrs):
        lat = attrs.get("latitude", getattr(self.instance, "latitude", None))
        lng = attrs.get("longitude", getattr(self.instance, "longitude", None))
        validate_coordinates(lat, lng)
        return attrs
