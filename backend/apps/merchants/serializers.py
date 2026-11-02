from rest_framework import serializers

from apps.categories.models import Category

from .models import MerchantProfile


class MerchantRegisterSerializer(serializers.Serializer):
    owner_name = serializers.CharField(max_length=150)
    business_category = serializers.PrimaryKeyRelatedField(queryset=Category.objects.filter(is_active=True))


class MerchantProfileSerializer(serializers.ModelSerializer):
    phone = serializers.CharField(source="user.phone", read_only=True)
    business_category_name = serializers.CharField(source="business_category.name", read_only=True)

    class Meta:
        model = MerchantProfile
        fields = [
            "id", "phone", "owner_name", "business_category", "business_category_name",
            "status", "rejection_reason", "created_at",
        ]
        read_only_fields = ["id", "status", "rejection_reason", "created_at"]
