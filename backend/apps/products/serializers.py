from rest_framework import serializers

from apps.categories.models import Category
from apps.shops.models import Shop
from common.validators import validate_image_file

from .models import Product, ProductImage


class ProductImageSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductImage
        fields = ["id", "image", "sort_order"]


class ProductSerializer(serializers.ModelSerializer):
    shop = serializers.PrimaryKeyRelatedField(queryset=Shop.objects.none())
    category = serializers.PrimaryKeyRelatedField(queryset=Category.objects.filter(is_active=True))
    category_name = serializers.CharField(source="category.name", read_only=True)
    images = ProductImageSerializer(many=True, read_only=True)

    class Meta:
        model = Product
        fields = [
            "id", "shop", "category", "category_name", "name", "description", "unit",
            "standard_price", "is_active", "images", "created_at",
        ]
        read_only_fields = ["id", "created_at"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        request = self.context.get("request")
        if request is not None and request.user.is_authenticated:
            # A merchant can only add products to their own shops.
            self.fields["shop"].queryset = Shop.objects.filter(merchant__user=request.user)
        if self.instance is not None:
            self.fields["shop"].read_only = True


class ProductImageUploadSerializer(serializers.Serializer):
    product = serializers.PrimaryKeyRelatedField(queryset=Product.objects.none())
    image = serializers.ImageField(validators=[validate_image_file])

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        request = self.context.get("request")
        if request is not None and request.user.is_authenticated:
            self.fields["product"].queryset = Product.objects.filter(shop__merchant__user=request.user)
