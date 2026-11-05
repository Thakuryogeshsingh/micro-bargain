from rest_framework import serializers

from .models import Review


class ReviewCreateSerializer(serializers.Serializer):
    reservation = serializers.IntegerField(required=False)
    order = serializers.IntegerField(required=False)
    rating = serializers.IntegerField(min_value=1, max_value=5)
    comment = serializers.CharField(required=False, allow_blank=True, max_length=1000)
    photo = serializers.ImageField(required=False)

    def validate(self, attrs):
        if ("reservation" in attrs) == ("order" in attrs):
            raise serializers.ValidationError("Send either reservation or order.")
        return attrs


class ReviewSerializer(serializers.ModelSerializer):
    customer_name = serializers.SerializerMethodField()

    class Meta:
        model = Review
        fields = ["id", "shop", "customer_name", "rating", "comment", "photo", "merchant_reply", "replied_at", "created_at"]

    def get_customer_name(self, obj) -> str:
        # First name only: reviews are public.
        return (obj.customer.name or "ग्राहक").split()[0]


class ReplySerializer(serializers.Serializer):
    reply = serializers.CharField(max_length=1000)
