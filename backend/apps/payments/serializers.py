from rest_framework import serializers

from .models import Payment, Refund


class PaymentCreateSerializer(serializers.Serializer):
    purpose = serializers.ChoiceField(choices=Payment.Purpose.choices)
    id = serializers.IntegerField(help_text="Order / subscription / advertisement id")


class PaymentVerifySerializer(serializers.Serializer):
    # Field names match what Razorpay Checkout returns to the app.
    razorpay_order_id = serializers.CharField(max_length=64)
    razorpay_payment_id = serializers.CharField(max_length=64)
    razorpay_signature = serializers.CharField(max_length=128)


class RefundSerializer(serializers.ModelSerializer):
    class Meta:
        model = Refund
        fields = ["id", "amount", "reason", "status", "created_at"]


class PaymentSerializer(serializers.ModelSerializer):
    refunds = RefundSerializer(many=True, read_only=True)
    reference = serializers.SerializerMethodField()

    class Meta:
        model = Payment
        fields = ["id", "purpose", "reference", "amount", "currency", "status", "method", "error", "paid_at",
                  "refunds", "created_at"]

    def get_reference(self, obj) -> str:
        if obj.order_id:
            return obj.order.order_number
        if obj.membership_id:
            return f"PLUS-{obj.membership_id}"
        return f"SUB-{obj.subscription_id}" if obj.subscription_id else f"AD-{obj.advertisement_id}"


class CheckoutSerializer(serializers.Serializer):
    """What the app passes to Razorpay Checkout."""

    payment_id = serializers.IntegerField()
    key_id = serializers.CharField()
    razorpay_order_id = serializers.CharField()
    amount = serializers.IntegerField(help_text="In paise")
    currency = serializers.CharField()
    name = serializers.CharField()
    description = serializers.CharField()
    prefill_contact = serializers.CharField()
