from rest_framework import serializers

from .models import Complaint, ComplaintMessage


class ComplaintMessageSerializer(serializers.ModelSerializer):
    class Meta:
        model = ComplaintMessage
        fields = ["id", "is_staff_reply", "message", "created_at"]


class ComplaintSerializer(serializers.ModelSerializer):
    messages = ComplaintMessageSerializer(many=True, read_only=True)

    class Meta:
        model = Complaint
        fields = ["id", "ticket_number", "category", "subject", "order", "reservation", "status", "priority",
                  "resolved_at", "created_at", "messages"]


class ComplaintCreateSerializer(serializers.Serializer):
    category = serializers.ChoiceField(choices=Complaint.Category.choices)
    subject = serializers.CharField(max_length=150)
    message = serializers.CharField(max_length=2000)
    order = serializers.IntegerField(required=False)
    reservation = serializers.IntegerField(required=False)


class MessageSerializer(serializers.Serializer):
    message = serializers.CharField(max_length=2000)
