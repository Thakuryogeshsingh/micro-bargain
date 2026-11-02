from decimal import Decimal

from django.conf import settings
from django.utils import timezone
from rest_framework import serializers

from apps.products.models import Product
from apps.shops.models import Shop
from common.validators import validate_coordinates

from .models import Deal
from .services import SORTS

QUANTITY = {"max_digits": 10, "decimal_places": 2, "min_value": 0}
PRICE = {"max_digits": 10, "decimal_places": 2}


class DealCreateSerializer(serializers.Serializer):
    shop = serializers.PrimaryKeyRelatedField(queryset=Shop.objects.none())
    product = serializers.PrimaryKeyRelatedField(queryset=Product.objects.none())
    normal_price = serializers.DecimalField(**PRICE, required=False, help_text="Defaults to the product's standard price.")
    offer_price = serializers.DecimalField(**PRICE)
    quantity_total = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=Decimal("0.01"))
    starts_at = serializers.DateTimeField(required=False, help_text="Defaults to now.")
    expires_at = serializers.DateTimeField(required=False)
    duration_minutes = serializers.IntegerField(required=False, min_value=15, help_text="Use instead of expires_at.")
    description = serializers.CharField(required=False, allow_blank=True, default="")
    image = serializers.ImageField(required=False)
    fulfilment = serializers.ChoiceField(choices=Deal.Fulfilment.choices, default=Deal.Fulfilment.PICKUP)
    publish = serializers.BooleanField(default=False, help_text="Publish immediately after creating.")

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        request = self.context.get("request")
        if request is not None and request.user.is_authenticated:
            # Scoping the choices means a merchant can only use their own shops and products.
            self.fields["shop"].queryset = Shop.objects.filter(merchant__user=request.user)
            self.fields["product"].queryset = Product.objects.filter(shop__merchant__user=request.user)


class DealUpdateSerializer(serializers.Serializer):
    normal_price = serializers.DecimalField(**PRICE, required=False)
    offer_price = serializers.DecimalField(**PRICE, required=False)
    expires_at = serializers.DateTimeField(required=False)
    description = serializers.CharField(required=False, allow_blank=True)
    fulfilment = serializers.ChoiceField(choices=Deal.Fulfilment.choices, required=False)
    image = serializers.ImageField(required=False)


class StockUpdateSerializer(serializers.Serializer):
    quantity_total = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=Decimal("0.01"))


class DealShopSerializer(serializers.ModelSerializer):
    latitude = serializers.FloatField(read_only=True)
    longitude = serializers.FloatField(read_only=True)

    class Meta:
        model = Shop
        fields = ["id", "name", "address_line", "city", "latitude", "longitude", "rating_avg", "rating_count"]


class DealSerializer(serializers.ModelSerializer):
    """Customer-facing deal card / detail."""

    shop = DealShopSerializer(read_only=True)
    product_id = serializers.IntegerField(source="product.id", read_only=True)
    product_name = serializers.CharField(source="product.name", read_only=True)
    category = serializers.IntegerField(source="product.category_id", read_only=True)
    category_name = serializers.CharField(source="product.category.name", read_only=True)
    image = serializers.SerializerMethodField()
    quantity_available = serializers.DecimalField(**QUANTITY, read_only=True)
    seconds_left = serializers.SerializerMethodField()
    distance_m = serializers.SerializerMethodField()
    is_featured = serializers.SerializerMethodField()

    class Meta:
        model = Deal
        fields = [
            "id", "shop", "product_id", "product_name", "category", "category_name", "description", "image",
            "unit", "normal_price", "offer_price", "discount_percent", "quantity_available",
            "starts_at", "expires_at", "seconds_left", "fulfilment", "status", "published_at", "distance_m",
            "is_featured",
        ]

    def get_image(self, obj) -> str | None:
        image = obj.image or next((i.image for i in obj.product.images.all()), None)
        if not image:
            return None
        request = self.context.get("request")
        return request.build_absolute_uri(image.url) if request else image.url

    def get_seconds_left(self, obj) -> int:
        return max(0, int((obj.expires_at - timezone.now()).total_seconds()))

    def get_is_featured(self, obj) -> bool:
        return bool(getattr(obj, "is_featured", False))

    def get_distance_m(self, obj) -> int | None:
        distance = getattr(obj, "distance", None)
        return round(distance.m) if distance is not None else None


class MerchantDealSerializer(DealSerializer):
    """The merchant's view adds the stock breakdown."""

    class Meta(DealSerializer.Meta):
        fields = DealSerializer.Meta.fields + ["quantity_total", "quantity_reserved", "quantity_sold", "created_at"]


class NearbyDealsQuerySerializer(serializers.Serializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    radius = serializers.ChoiceField(choices=settings.ALLOWED_SEARCH_RADII_METERS, default=settings.DEFAULT_SEARCH_RADIUS_METERS)
    category = serializers.IntegerField(required=False)
    min_price = serializers.DecimalField(**PRICE, required=False)
    max_price = serializers.DecimalField(**PRICE, required=False)
    min_discount = serializers.DecimalField(max_digits=5, decimal_places=2, required=False)
    min_rating = serializers.DecimalField(max_digits=3, decimal_places=2, required=False)
    q = serializers.CharField(required=False, max_length=100)
    fulfilment = serializers.ChoiceField(choices=[Deal.Fulfilment.PICKUP, Deal.Fulfilment.DELIVERY], required=False)
    sort = serializers.ChoiceField(choices=list(SORTS), default="distance")

    def validate(self, attrs):
        validate_coordinates(attrs["latitude"], attrs["longitude"])
        return attrs
