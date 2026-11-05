from django.conf import settings
from rest_framework import serializers

from apps.categories.models import Category
from common.validators import validate_coordinates

from .models import Shop, ShopDocument


class ShopWriteSerializer(serializers.ModelSerializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6, write_only=True)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6, write_only=True)
    category = serializers.PrimaryKeyRelatedField(queryset=Category.objects.filter(is_active=True))

    class Meta:
        model = Shop
        fields = [
            "name", "description", "category", "phone", "cover_image",
            "address_line", "landmark", "city", "state", "pincode", "latitude", "longitude",
            "opening_time", "closing_time", "prep_minutes", "happy_hour_enabled", "happy_hour_percent", "happy_hour_minutes",
            "offers_pickup", "offers_delivery", "is_temporarily_closed",
        ]

    def validate(self, attrs):
        lat, lng = attrs.get("latitude"), attrs.get("longitude")
        if (lat is None) != (lng is None):
            raise serializers.ValidationError("Send latitude and longitude together.")
        if lat is not None:
            validate_coordinates(lat, lng)
        return attrs


class ShopSerializer(serializers.ModelSerializer):
    """The merchant's own view of a shop, including review status."""

    category_name = serializers.CharField(source="category.name", read_only=True)
    latitude = serializers.FloatField(read_only=True)
    longitude = serializers.FloatField(read_only=True)

    class Meta:
        model = Shop
        fields = [
            "id", "name", "description", "category", "category_name", "phone", "cover_image",
            "address_line", "landmark", "city", "state", "pincode", "latitude", "longitude",
            "opening_time", "closing_time", "prep_minutes", "happy_hour_enabled", "happy_hour_percent", "happy_hour_minutes",
            "offers_pickup", "offers_delivery", "is_temporarily_closed",
            "status", "rejection_reason", "rating_avg", "rating_count", "created_at",
        ]
        read_only_fields = fields


class PublicShopSerializer(serializers.ModelSerializer):
    """What customers see. `distance_m` is present when the query annotated a distance."""

    category_name = serializers.CharField(source="category.name", read_only=True)
    latitude = serializers.FloatField(read_only=True)
    longitude = serializers.FloatField(read_only=True)
    distance_m = serializers.SerializerMethodField()
    is_favorite = serializers.SerializerMethodField()
    # Present when the query added deal stats (nearby list, shop page).
    live_deals_count = serializers.IntegerField(read_only=True, default=0)
    max_discount = serializers.DecimalField(max_digits=5, decimal_places=2, read_only=True, default=None)

    class Meta:
        model = Shop
        fields = [
            "id", "name", "description", "category", "category_name", "phone", "cover_image",
            "address_line", "landmark", "city", "pincode", "latitude", "longitude",
            "opening_time", "closing_time", "prep_minutes", "happy_hour_enabled", "happy_hour_percent", "offers_pickup", "offers_delivery",
            "rating_avg", "rating_count", "distance_m", "is_favorite", "live_deals_count", "max_discount",
        ]

    def get_distance_m(self, obj) -> int | None:
        distance = getattr(obj, "distance", None)
        return round(distance.m) if distance is not None else None

    def get_is_favorite(self, obj) -> bool:
        favorite_ids = self.context.get("favorite_ids")
        return obj.id in favorite_ids if favorite_ids is not None else False


class NearbyQuerySerializer(serializers.Serializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    radius = serializers.ChoiceField(choices=settings.ALLOWED_SEARCH_RADII_METERS, default=settings.DEFAULT_SEARCH_RADIUS_METERS)
    category = serializers.IntegerField(required=False)

    def validate(self, attrs):
        validate_coordinates(attrs["latitude"], attrs["longitude"])
        return attrs


class ShopDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = ShopDocument
        fields = ["id", "doc_type", "file", "status", "remarks", "created_at"]
        read_only_fields = ["id", "status", "remarks", "created_at"]
