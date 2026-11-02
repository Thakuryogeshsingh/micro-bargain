from rest_framework import serializers

from .models import MerchantSubscription, Plan


class PlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = Plan
        fields = ["code", "name", "price_monthly", "max_active_deals", "analytics", "featured_listing", "priority_support"]


class SubscriptionSerializer(serializers.ModelSerializer):
    plan = PlanSerializer(read_only=True)

    class Meta:
        model = MerchantSubscription
        fields = ["id", "plan", "months", "amount", "status", "starts_at", "ends_at", "created_at"]


class SubscribeSerializer(serializers.Serializer):
    plan = serializers.SlugField()
    months = serializers.IntegerField(min_value=1, max_value=12, default=1)
