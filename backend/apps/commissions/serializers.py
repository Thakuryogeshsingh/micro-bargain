from rest_framework import serializers

from .models import Commission


class CommissionSerializer(serializers.ModelSerializer):
    source = serializers.SerializerMethodField()

    class Meta:
        model = Commission
        fields = ["id", "source", "transaction_amount", "amount", "status", "settled_at", "settlement_reference", "created_at"]

    def get_source(self, obj) -> str:
        return obj.order.order_number if obj.order_id else obj.reservation.reservation_number
