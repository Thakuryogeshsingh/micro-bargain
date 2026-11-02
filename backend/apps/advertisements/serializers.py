from rest_framework import serializers

from apps.deals.models import Deal
from common.validators import validate_coordinates, validate_image_file

from .models import Advertisement


class AdCreateSerializer(serializers.Serializer):
    placement = serializers.ChoiceField(choices=Advertisement.Placement.choices)
    days = serializers.IntegerField(min_value=1)
    deal = serializers.PrimaryKeyRelatedField(queryset=Deal.objects.all(), required=False)
    title = serializers.CharField(required=False, allow_blank=True, max_length=80)
    banner_image = serializers.ImageField(required=False, validators=[validate_image_file])
    radius_m = serializers.ChoiceField(choices=[1000, 2000, 5000, 10000], default=5000)


class AdvertisementSerializer(serializers.ModelSerializer):
    class Meta:
        model = Advertisement
        fields = ["id", "placement", "deal", "title", "banner_image", "radius_m", "days", "price", "status",
                  "starts_at", "ends_at", "rejection_reason", "impressions", "clicks", "created_at"]


class BannerSerializer(serializers.ModelSerializer):
    shop_id = serializers.IntegerField(source="shop.id")
    shop_name = serializers.CharField(source="shop.name")

    class Meta:
        model = Advertisement
        fields = ["id", "title", "banner_image", "shop_id", "shop_name"]


class BannerQuerySerializer(serializers.Serializer):
    latitude = serializers.FloatField()
    longitude = serializers.FloatField()

    def validate(self, attrs):
        validate_coordinates(attrs["latitude"], attrs["longitude"])
        return attrs
