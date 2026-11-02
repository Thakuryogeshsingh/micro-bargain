from rest_framework import serializers

from common.validators import validate_coordinates

from .models import Device, Notification


class DeviceRegisterSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=255)
    platform = serializers.ChoiceField(choices=Device.Platform.choices, default=Device.Platform.ANDROID)
    latitude = serializers.FloatField(required=False)
    longitude = serializers.FloatField(required=False)

    def validate(self, attrs):
        has_lat, has_lng = "latitude" in attrs, "longitude" in attrs
        if has_lat != has_lng:
            raise serializers.ValidationError("Send both latitude and longitude, or neither.")
        if has_lat:
            validate_coordinates(attrs["latitude"], attrs["longitude"])
        return attrs


class DeviceTokenSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=255)


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ["id", "kind", "title", "body", "data", "is_read", "read_at", "created_at"]
